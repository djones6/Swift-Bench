Usage:
./drive.sh run_name [cpu list] [clients list] [duration] [app] [url] [instances]
cpu list = comma-separated list of CPUs to affinitize the application to (eg: 0,1,2,3)
clients list = number of simultaneous clients to simulate. This can be a comma-separated list, for example to simulate ramp-up. Separate statistics will be reported for each load period
duration = time (seconds) for each load period
app = full path name to the executable under test
url = URL to drive load against (or for JMeter, the driver script to use)
instances = number of concurrent instances of app to start (default 1)

Workload driver

By default, 'wrk' is used to drive load. You can set the environment variable DRIVER to either 'wrk' or 'jmeter'.  Ensure that the command is available in your PATH.

Profiling

Various profiling options are provided for Linux (you must install these tools as appropriate on your system, all are readily available through the package manager).

To enable, set environment variable PROFILER to one of the following:

valgrind - produces a report of memory leaks using massif

oprofile - profiles the application only, using 'oprofile'
The report is generated in two formats: plain text (flat and callgraph), and an XML format.

oprofile-sys - profiles the whole system (requires sudo)
To get Kernel debug symbols on Ubuntu, see:
http://superuser.com/questions/62575/where-is-vmlinux-on-my-ubuntu-installation/309589#309589

perf - profiles the application only, using 'perf'
Two reports are generated: a flat profile, and the call graph.
