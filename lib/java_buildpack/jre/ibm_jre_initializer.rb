# Cloud Foundry Java Buildpack
# Copyright 2017 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'digest'
require 'fileutils'
require 'java_buildpack/component/versioned_dependency_component'
require 'java_buildpack/jre'
require 'java_buildpack/util/tokenized_version'

module JavaBuildpack
  module Jre

    # Encapsulates the detect, compile, and release functionality for selecting a JRE.
    class IbmJreInitializer < JavaBuildpack::Component::VersionedDependencyComponent

      # Creates an instance
      #
      # @param [Hash] context a collection of utilities used the component
      def initialize(context)
        @application    = context[:application]
        @component_name = context[:component_name]
        @configuration  = context[:configuration]
        @droplet        = context[:droplet]

        @droplet.java_home.root = @droplet.sandbox + 'jre/'
      end

      # (see JavaBuildpack::Component::BaseComponent#detect)
      def detect
        @version, @uri             = JavaBuildpack::Repository::ConfiguredItem.find_item(@component_name,
                                                                                         @configuration)
        @droplet.java_home.version = @version
        super
      end

      # (see JavaBuildpack::Component::BaseComponent#compile)
      def compile
        download(@version, @uri['uri'], @component_name) do |file|
          check_sha256(file, @uri['sha256sum'])
          with_timing "Installing #{@component_name} to #{@droplet.sandbox.relative_path_from(@droplet.root)}" do
            install_bin(@droplet.sandbox, file)
          end
        end
        @droplet.copy_resources
      end

      # (see JavaBuildpack::Component::BaseComponent#release)
      def release
        @droplet
          .java_opts
          .add_system_property('java.io.tmpdir', '$TMPDIR')
        @droplet.java_opts << '-Xtune:virtualized'
        @droplet.java_opts.concat mem_opts
        @droplet.java_opts.concat tls_opts
        @droplet.java_opts << '-Xshareclasses:none'
      end

      private

      # constant HEAP_RATIO is the ratio of memory assigned to the heap
      # as against the container total and is set using -Xmx.
      HEAP_RATIO = 0.75

      KILO = 1024

      # Installs the Downloaded InstallAnywhere (tm) BIN file to the target directory
      #
      # @param [String] target_directory, Where the java needs to be installed
      # @param [File] file, InstallAnywhere (tm) BIN file
      # @return [Void]
      def install_bin(target_directory, file)
        FileUtils.mkdir_p target_directory
        response_file = Tempfile.new('response.properties')
        response_file.puts('INSTALLER_UI=silent')
        response_file.puts('LICENSE_ACCEPTED=TRUE')
        response_file.puts("USER_INSTALL_DIR=#{target_directory}")
        response_file.close

        File.chmod(0o755, file.path) unless File.executable?(file.path)
        shell "#{file.path} -i silent -f #{response_file.path} 2>&1"
      end

      # Checks the SHA256 Checksum of the file
      #
      # @param [File] file, The downloaded file
      # @param [String] checksum, The string containing the SHA256 of the file
      def check_sha256(file, checksum)
        raise 'sha256 checksum does not match' unless Digest::SHA256.hexdigest(File.read(file.path)) == checksum
      end

      # Returns the max heap size ('-Xmx') value
      def mem_opts
        mopts = []
        total_memory = memory_limit_finder
        if total_memory.nil?
          # if no memory option has been set by cloudfoundry, we just assume defaults
        else
          calculated_heap_ratio = heap_ratio_verification(heap_ratio)
          heap_size = heap_size_calculator(total_memory, calculated_heap_ratio)
          mopts.push "-Xmx#{heap_size}"
        end
        mopts
      end

      # Returns the heap_ratio attribute in config file (if specified) or the HEAP_RATIO constant value
      def heap_ratio
        @configuration['heap_ratio'] || HEAP_RATIO
      end

      def tls_opts
        opts = []
        # enable all TLS protocols when SSLContext.getInstance("TLS") is called
        opts << '-Dcom.ibm.jsse2.overrideDefaultTLS=true'
        opts
      end

      # Returns the container total memory limit in bytes
      def memory_limit_finder
        memory_limit = ENV['MEMORY_LIMIT']
        return nil unless memory_limit
        memory_limit_size = memory_size_bytes(memory_limit)
        raise "Invalid negative $MEMORY_LIMIT #{memory_limit}" if memory_limit_size < 0
        memory_limit_size
      end

      # Returns the no. of bytes for a given string of minified size representation
      #
      # @param [String] size, A minified memory representation string
      # @return [Integer] bytes, value of size in bytes
      def memory_size_bytes(size)
        if size == '0'
          bytes = 0
        else
          raise "Invalid memory size '#{size}'" if !size || size.length < 2
          unit = size[-1]
          value = size[0..-2]
          raise "Invalid memory size '#{size}'" unless check_is_integer? value
          value = size.to_i
          # store the bytes
          bytes = calculate_bytes(unit, value)
        end
        bytes
      end

      # Returns the no. of bytes for a given memory size unit
      #
      # @param [String] unit, Represents a Memory Size Unit
      # @param [Integer] value
      # @return [Integer] bytes, value of size in bytes
      def calculate_bytes(unit, value)
        if unit == 'b' || unit == 'B'
          bytes = value
        elsif unit == 'k' || unit == 'K'
          bytes = KILO * value
        elsif unit == 'm' || unit == 'M'
          bytes = KILO * KILO * value
        elsif unit == 'g' || unit == 'G'
          bytes = KILO * KILO * KILO * value
        else
          raise "Invalid unit '#{unit}' in memory size"
        end
        bytes
      end

      # Checks whether the given value is an Integer
      #
      # @param [String] v, value as a string
      def check_is_integer?(v)
        v = Float(v)
        v && v.floor == v
      end

      # Calculates the Heap size as per the Heap ratio
      #
      # @param [Integer] membytes, total memory in bytes
      # @param [Numeric] heapratio, Desired/Default Heap Ratio
      def heap_size_calculator(membytes, heapratio)
        memory_size_minified(membytes * heapratio)
      end

      # Calculates the Memory Size in a Minified String Representation
      #
      # @param [Numeric] membytes, calculated heap size
      def memory_size_minified(membytes)
        giga = membytes / 2**(10 * 3)
        mega = membytes / 2**(10 * 2)
        kilo = (membytes / 2**(10 * 1)).round
        if check_is_integer?(giga)
          minified_size_calculator(giga, 'G')
        elsif check_is_integer?(mega)
          minified_size_calculator(mega, 'M')
        elsif check_is_integer?(kilo)
          minified_size_calculator(kilo, 'K')
        end
      end

      # Returns the minified memory string
      #
      # @param [Integer] order, calculated memory value
      # @param [String] char, calculated memory unit
      # @return [String] minified memory string
      def minified_size_calculator(order, char)
        order.to_i.to_s + char
      end

      # Verifies whether heap ratio is valid
      def heap_ratio_verification(ratio)
        raise 'Invalid heap ratio' unless ratio.is_a? Numeric
        raise 'heap ratio cannot be greater than 100%' unless ratio <= 1
        ratio
      end

    end

  end
end
