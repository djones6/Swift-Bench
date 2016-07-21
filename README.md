A performance benchmark harness for testing web frameworks, which offers the convenience of running CPU and RSS (resident set) monitoring in the background. CPU affinity is supported on Linux.

It is essentially a small collection of bash scripts, calling out to standard tools such as sed, awk, some optional system utilities such as mpstat, and various workload drivers such as wrk.

This is firmly a work in progress and growing features as I need them. Contributions, fixes and improvements are welcome!

###Usage:
`./drive.sh run_name [cpu list] [clients list] [duration] [app] [url] [instances] [rate list]`
- cpu list = comma-separated list of CPUs to affinitize the application to (eg: 0,1,2,3)
  - only supported on Linux. This param is ignored on Mac
- clients list = number of simultaneous clients to simulate. This can be a comma-separated list, for example to simulate ramp-up. Separate statistics will be reported for each load period
- duration = time (seconds) for each load period
- app = full path name to the executable under test
- url = URL to drive load against (or for JMeter, the driver script to use)
- instances = number of concurrent instances of app to start (default 1)
- rate list = comma-separated list of constant load levels (rps) to drive (only for wrk2)

Results and output files are stored under a subdirectory `runs/<run name>/`

`./compare.sh [app1] ... [appN]`
- Wrapper for `drive.sh`, running a compare of multiple applications and repeating for a number of iterations. At the end of the runs, a table of results is produced for easy consumption.
- The output from the runs is stored in `runs/compare_<iteration no>_<app no>/`
- The original output from `drive.sh` is preserved in a series of files named `compare_<iteration no>_<app no>.out`.
- Compares can be customized by setting various environment variables:
```
```

###Workload driver

You can set the environment variable DRIVER to either
- wrk (https://github.com/wg/wrk) - highly efficient, variable-rate load generator
- wrk2 (https://github.com/giltene/wrk2) - fixed-rate wrk variant with accurate latency stats
- jmeter (http://jmeter.apache.org/) - highly customizable Java-based load generator

By default, 'wrk' is used to drive load.  Ensure that the command is available in your PATH.

###Profiling

Various profiling options are provided for Linux (you must install these tools as appropriate on your system, all are readily available through the package manager).

To enable, set environment variable PROFILER to one of the following:
- valgrind - produces a report of memory leaks using massif
- oprofile - profiles the application only, using 'oprofile'
  - The report is generated in two formats: plain text (flat and callgraph), and an XML format.
- oprofile-sys - profiles the whole system (requires sudo)
  - To get Kernel debug symbols on Ubuntu, see:
  - http://superuser.com/questions/62575/where-is-vmlinux-on-my-ubuntu-installation/309589#309589
- perf - profiles the application only, using 'perf'
  - Two reports are generated: a flat profile, and the call graph.
