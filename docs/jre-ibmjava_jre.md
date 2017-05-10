# IBMJAVA JRE
IBMJAVA JRE provides Java runtimes developed by IBMJAVA team.  Version of Java `1.8` level is available.  Unless otherwise configured, the version of Java that will be used is specified in [`config/ibmjava_jre.yml`][].


## Configuration
For general information on configuring the buildpack, including how to specify configuration values through environment variables, refer to [Configuration and Extension][].

The JRE can be configured by modifying the [`config/ibmjava_jre.yml`][] file in the buildpack fork.  The JRE uses the [`Repository` utility support][repositories] and so, it supports the [version syntax][]  defined there.

To use IBMJAVA JRE instead of OpenJDK without forking java-buildpack, set environment variable:

`cf set-env <app_name> JBP_CONFIG_COMPONENTS '{jres: ["JavaBuildpack::Jre::IbmjavaJRE"]}'`

`cf restage <app_name>`

| Name | Description
| ---- | -----------
| `repository_root` | The URL of the IBMJAVA repository index ([details][repositories]).
| `version` | The version of Java runtime to use.

### Additional Resources
The JRE can also be configured by overlaying a set of resources on the default distribution. To do this, add files to the `resources/ibmjava_jre` directory in the buildpack fork.

#### Custom CA Certificates
To add custom SSL certificates, add your `cacerts` file to `resources/ibmjava_jre/jre/lib/security/cacerts`.  This file will be overlayed onto the IBMJAVA distribution.

### Memory
The total available memory for the application's container is specified when an application is pushed.
The Java buildpack uses this value to control the JRE's use of various
regions of memory and logs the JRE memory settings when the application starts or restarts.

Note: If the total available memory is scaled up or down, the Java buildpack will re-calculate the JRE memory settings the next time the application is started.

#### Total Memory
The user can change the container's total memory available to influence the JRE memory settings.
Unless the user specifies the heap size Java option (`-Xmx`), increasing or decreasing the total memory
available results in the heap size setting increasing or decreasing by a corresponding amount.

#### Memory Calculation
The user can configure the desired heap ratio (`-Xmx`) by changing the `heap_ratio` attribute under `jre` in [`config/ibmjava_jre.yml`][]
and the buildpack calculates the `-Xmx Memory Setting` based on the total memory available 


The container's total memory is logged during `cf push` and `cf scale`, for example:
```
     state     since                    cpu    memory       disk         details
#0   running   2017-04-10 02:20:03 PM   0.0%   896K of 1G   1.3M of 1G
```

[`config/components.yml`]: ../config/components.yml
[`config/ibmjava_jre.yml`]: ../config/ibmjava_jre.yml
[Configuration and Extension]: ../README.md#configuration-and-extension
[repositories]: extending-repositories.md
[version syntax]: extending-repositories.md#version-syntax-and-ordering
