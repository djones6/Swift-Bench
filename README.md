A performance benchmark harness for testing web frameworks, which offers the convenience of running CPU and RSS (resident set) monitoring in the background. CPU affinity is supported on Linux.

It is essentially a small collection of bash scripts, calling out to standard tools such as sed, awk, some optional system utilities such as mpstat, and various workload drivers such as wrk.

This is firmly a work in progress and growing features as I need them. Contributions, fixes and improvements are welcome!

##Requirements:
On Mac, there are no prereqs other than a suitable workload driver (see below).
On Linux, you may additionally want to install:
- `mpstat` (Ubuntu: `sudo apt-get install sysstat`)
- `numactl` if not already installed (`sudo apt-get install numactl)`

##Usage:
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

###Comparing multiple implementations:

`./compare.sh [app1] ... [appN]`
- Wrapper for `drive.sh`, running a compare of multiple applications and repeating for a number of iterations. At the end of the runs, a table of results is produced for easy consumption.
- The output from the runs is stored in `compares/<date>/runs/compare_<iteration no>_<app no>/`
- The original output from `drive.sh` is preserved in a series of files named `compares/<date>/compare_<iteration no>_<app no>.out`.
- Compares can be customized by setting various environment variables:
```
  ITERATIONS: number of repetitions of each implementation (default: 5)
  URL: url to drive load against (default: http://127.0.0.1:8080/plaintext)
  CPUS: list of CPUs to affinitize to (default: 0,1,2,3)
  CLIENTS: # of concurrent clients (default: 128)
  DURATION: time (sec) to apply load (default: 30)
```
If you require multiple instances of the application, specify the application path and number of instances separated by a comma, for example: `/path/to/executable,iterations`

##Example output

Output from `compare.sh` is in the following format:
```
Implementation | Avg Throughput | Max Throughput | Avg CPU | Avg RSS (kb)
---------------|----------------|----------------|---------|--------------
             1 |        38122.0 |       38609.66 |    88.6 |       793990
             2 |        33068.6 |       33508.57 |    99.9 |        53444
             3 |         3196.4 |        3196.90 |    10.1 |        42287
 ```
This is a simple summarization of the output from each run of each implementation. Further details for each measurement can be found by examining the `compare_<iteration no>_<app no>.out` files.

###Regenerating the output from a previous compare

As a convenience, to regenerate the output from a previous compare, use:
`./recompare.sh <date>` where `<date>` is one of the subdirectories under `compares`.

Recompare will automatically determine which applications you compared. However, if you set any environment variables for your original compare (such as changing the number of iterations), you must set them to the same values when running recompare.

##Workload driver

You can set the environment variable `DRIVER` to either
- wrk (https://github.com/wg/wrk) - highly efficient, variable-rate load generator
- wrk2 (https://github.com/giltene/wrk2) - fixed-rate wrk variant with accurate latency stats
- jmeter (http://jmeter.apache.org/) - highly customizable Java-based load generator

By default, 'wrk' is used to drive load.  Ensure that the command is available in your PATH.

###Driving requests remotely

You can set the environment variable `CLIENT` to the hostname of another server which will act as the client driver. In this case, you must also set the URL parmeter to be appropriate from the client server's perspective. As an example:
- `myserver.mydomain.com` - system under test (execute the driver script here)
- `myclient.mydomain.com` - system to use as a client
- `env CLIENT=myclient ./drive.sh ..... http://myserver:8080/plaintext`

When `CLIENT` is set, the driver command will be issued via `ssh -t $CLIENT`. In order for this to work, you must allow `myserver` to issue SSH commands on `myclient` with the same userid and without prompting for a password. This can typically be achieved through the use of public key authentication.
Also, you must ensure that the workload driver `wrk` is installed and present on your `PATH` on the client system.

##Profiling

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
