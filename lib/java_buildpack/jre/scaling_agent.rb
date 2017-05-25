# Cloud Foundry Java Buildpack
# Copyright 2016 the original author or authors.
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

require 'fileutils'
require 'java_buildpack/component/versioned_dependency_component'
require 'java_buildpack/jre'

module JavaBuildpack
  module Jre

    # Encapsulates the detect, compile, and release functionality for the jvmkill agent
    class ScalingAgent < JavaBuildpack::Component::VersionedDependencyComponent
      include JavaBuildpack::Util

      # (see JavaBuildpack::Component::BaseComponent#compile)
      def compile
        download(@version, @uri) do |file|
          FileUtils.mkdir_p scaling_agent.parent
          FileUtils.cp(file.path, scaling_agent)
          scaling_agent.chmod 0o755
        end
      end

      # (see JavaBuildpack::Component::BaseComponent#release)
      def release
        @droplet.java_opts.add_javaagent(scaling_agent)
      end

      protected

      # (see JavaBuildpack::Component::VersionedDependencyComponent#supports?)
      def supports?
        true
      end

      private

      def scaling_agent
        @droplet.sandbox + "bin/scalingagent-#{@version}"
      end

    end

  end
end
