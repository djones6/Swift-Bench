#!/bin/bash
# author: David Jones (djones6)
#
# Driver script to measure web server throughput and response time using Wrk.
# To use this, you need:
# 1) Wrk installed, and symlinked to ./wrk
# 2) A Kitura (or similar) application built and ready to run
# 3) The 'mpstat' utility installed (if you want per-core CPU utilisation)
# 4) The 'numactl' utility installed (to control process affinity)
#
# Customize this script for your machine. I'm running on a 2-socket machine,
# with the server running on the first socket and wrk running on the second.
# Change the args to numactl below so they make sense for your system.
#

RUN_NAME=$1
CPULIST=$2
SAMPLES=$3
DURATION=$4
APP_CMD=$5
URL=$6
INSTANCES=$7
WORK_DIR=$PWD

# Select workload driver (client simulator) with DRIVER env variable
# (default: wrk)
DRIVER_CHOICES="wrk jmeter"
#DRIVER="wrk"

# Select profiler with PROFILER env variable
# (default: none)
PROFILER_CHOICES="valgrind oprofile oprofile-sys perf perf-cg perf-idle"
#PROFILER=""

SUPPORTED_OSES="Linux Darwin"

# Customize this section appropriately for your hardware
case `uname` in
Linux)
  DRIVER_AFFINITY="numactl --cpunodebind=1 --membind=1"
  APP_AFFINITY="numactl --physcpubind=$CPULIST --membind=0"
  WORK_THREADS=16
  ;;
Darwin)
  # Don't know if this is possible on OS X...
  DRIVER_AFFINITY=""
  APP_AFFINITY=""
  WORK_THREADS=4
  ;;
esac

# Check this OS is supported
if [[ ! $SUPPORTED_OSES =~ `uname` ]]; then
  echo "Unsupported operating system: `uname`"
  exit 1
fi

# Consume environment settings
if [ -z "$PROFILER" ]; then
  PROFILER=""
else
  if [[ ! $PROFILER_CHOICES =~ $PROFILER ]]; then
    echo "Unrecognized profiler option '$PROFILER'"
    echo "Supported choices: $PROFILER_CHOICES"
    exit 1
  fi
fi
if [ -z "$DRIVER" ]; then
  DRIVER="wrk"
  echo "Using default driver: $DRIVER"
else
  if [[ ! $DRIVER_CHOICES =~ $DRIVER ]]; then
    echo "Unrecognized driver option '$DRIVER'"
    echo "Supported choices: $DRIVER_CHOICES"
    exit 1
  fi
fi

# Consume cmdline args (simplest possible implementation for now)
if [ -z "$1" -o "$1" == "--help" ]; then
  echo "Usage: $0 <run name> <cpu list> <clients list> <duration> <app> <url> <instances>"
  echo " - eg: $0 my_run_4way 0,1,2,3 1,5,10,100,200 30 ~/kitura http://127.0.0.1:8080/hello 1"
  echo "  cpu list = comma-separated list of CPUs to affinitize to"
  echo "  client list = comma-separated list of # clients to drive load"
  echo "  duration = length of each load period (seconds)"
  echo "  app = app command to execute"
  echo "  url = URL to drive load against (or jmeter script)"
  echo "  instances = number of copies of <app> to start"
  exit 1
fi
# CPU list
if [ -z "$2" ]; then
  CPULIST="0,1,2,3"
  echo "CPU list not specified; using default of '$CPULIST'"
fi
# Clients list
if [ -z "$3" ]; then
  SAMPLES="128"
  echo "Clients list not specified; using default of '$SAMPLES'"
fi
# Duration
if [ -z "$4" ]; then
  DURATION=10
  echo "Duration not specified; using default of '$DURATION'"
fi
# App
if [ -z "$5" ]; then
  APP_CMD="$WORK_DIR/kitura"
  echo "App not specified, using default of '$APP_CMD'"
fi
# URL
if [ -z "$6" ]; then
  URL="http://127.0.0.1:8080/plaintext"
  echo "URL not specified, using default of '$URL'"
fi
if [ -z "$7" ]; then
  INSTANCES=1
  echo "INSTANCES not specified, using default of '$INSTANCES'"
fi

# Thanks to https://straypixels.net/getting-the-cpu-time-of-a-process-in-bash-is-difficult/
function getcputime {
    local pid=$1
    local clk_tck=$(getconf CLK_TCK)
    local cputime=0
    local stats=$(cat "/proc/$pid/stat")
    local statarr=($stats)
    local utime=${statarr[13]}
    local stime=${statarr[14]}
    local numthreads=${statarr[20]}
    local usec=$(bc <<< "scale=3; $utime / $clk_tck")
    local ssec=$(bc <<< "scale=3; $stime / $clk_tck")
    local totalsec=$(bc <<< "scale=3; $usec + $ssec")
    #echo "clk_tck usec ssec totalsec numthreads"
    echo "$clk_tck $usec $ssec $totalsec $numthreads"
}

# Measures the server using a specified number of clients + duration.
function do_sample {
  NUMCLIENTS=$1
  DURATION=$2
  echo "Running load with $NUMCLIENTS clients"
  
  case `uname` in
  Linux)
    # Start mpstat to monitor per-CPU utilization
    #
    MPSTAT_DUR=5
    if [ $DURATION -lt $MPSTAT_DUR ]; then
      MPSTAT_DUR=$DURATION  # Ensure at least one report generated for short runs
    fi
    env LC_ALL='en_GB.UTF-8' mpstat -P $CPULIST $MPSTAT_DUR > mpstat.$NUMCLIENTS &
    MPSTAT_PID=$!
    ;;
  Darwin)
    # Don't know how to do this yet
    ;;
  esac

  # Capture CPU cycles consumed by server before we apply load
  # (this avoids counting any CPU costs incurred during startup)
  for APP_PID in $APP_PIDS; do
    PRE_CPU=(`getcputime $APP_PID`)
    PRE_CPUS="$PRE_CPU,$PRE_CPUS"
  done

  # Execute driver
  case $DRIVER in
  jmeter)
    SCRIPT=$URL  # Until I think of something better
    echo $DRIVER_AFFINITY jmeter -n -t ${SCRIPT} -q $WORK_DIR/user.properties -JTHREADS=$NUMCLIENTS -JDURATION=$DURATION -JRAMPUP=0 -JWARMUP=0 | tee results.$NUMCLIENTS
    $DRIVER_AFFINITY jmeter -n -t ${SCRIPT} -q $WORK_DIR/user.properties -JTHREADS=$NUMCLIENTS -JDURATION=$DURATION -JRAMPUP=0 -JWARMUP=0 >> results.$NUMCLIENTS
    ;;
  wrk)
    # Number of connections must be >= threads
    [[ ${WORK_THREADS} -gt ${NUMCLIENTS} ]] && WORK_THREADS=${NUMCLIENTS}
    echo $DRIVER_AFFINITY wrk --timeout 30 --latency -t${WORK_THREADS} -c${NUMCLIENTS} -d${DURATION}s ${URL} | tee results.$NUMCLIENTS
    $DRIVER_AFFINITY wrk --timeout 30 --latency -t${WORK_THREADS} -c${NUMCLIENTS} -d${DURATION}s ${URL} 2>&1 | tee -a results.$NUMCLIENTS
    # For no keepalive you can do: -H "Connection: close"
    ;;
  *)
    echo "Unknown driver '$DRIVER'"
    ;;
  esac
  
  # Diff CPU cycles after load applied
  let i=0
  echo "CPU consumed per instance:" | tee cpu.$NUMCLIENTS
  for APP_PID in $APP_PIDS; do
    let i=$i+1
    PRE_CPU=`echo $PRE_CPUS | cut -d',' -f${i}`
    POST_CPU=(`getcputime $APP_PID`)
    usec=$(bc <<< "${POST_CPU[1]} - ${PRE_CPU[1]}")
    ssec=$(bc <<< "${POST_CPU[2]} - ${PRE_CPU[2]}")
    totalsec=$(bc <<< "${POST_CPU[3]} - ${PRE_CPU[3]}")
    echo "$i: CPU time delta: user=$usec sys=$ssec total=$totalsec" | tee -a cpu.$NUMCLIENTS
  done

  # Post-process driver output
  case $DRIVER in
  jmeter)
    # Cherry-pick useful information from JMeter summary
    SUMMARY=`grep 'summary +' results.$NUMCLIENTS | tail -n 4 | head -n 3`
    echo "Summary from final 3 intervals of JMeter output:"
    echo $SUMMARY | awk '
      BEGIN {
        min=0;
        max=0;
        avg=0;
        thruput=0;
        count=0
      }
      /summary \+ / {
        min=(min < $11 ? min : $11);
        max=(max > $13 ? max : $13);
        avg += $9;
        sub("/s", "", $7);
        thruput += $7;
        count ++
      }
      END { 
        avg=avg/count;
        thruput=thruput/count;
        print "Min: " min " ms,  Max: " max " ms,  Avg: " avg " ms,  Thruput: " thruput " resp/sec"
      }'
    ;;
  wrk)
    # Nothing to do
    ;;
  *)
    ;;
  esac

  case `uname` in
  Linux)
  # Stop mpstat
  kill $MPSTAT_PID
  wait $MPSTAT_PID 2>/dev/null
  # Post-process output
  #
  # mpstat produces output in the following format:
  # 14:06:05     CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest  %gnice   %idle
  # 14:06:05     <n>    0.04    0.00    0.01    0.00    0.00    0.00    0.00    0.00    0.00   99.95
  #
  # Sum 100 - %idle (12) for each sample
  # Then divide by the number of samples collection ran for
  echo "CPU utilization by processor number:" | tee -a cpu.$NUMCLIENTS
  let NUM_CPUS=0
  TOTAL_CPU=0
  for CPU in `echo $CPULIST | tr ',' ' '`; do
    NUM_CYCLES=`cat mpstat.$NUMCLIENTS | grep -e"..:..:.. \+${CPU}" | wc -l`
    AVG_CPU=`cat mpstat.$NUMCLIENTS | grep -e"..:..:.. \+${CPU}" | awk -v SAMPLES=${NUM_CYCLES} '{TOTAL = TOTAL + (100 - $12) } END {printf "%.1f",TOTAL/SAMPLES}'`
    TOTAL_CPU=`echo $AVG_CPU | awk -v RTOT=$TOTAL_CPU '{print RTOT+$1}'`
    echo "CPU $CPU: $AVG_CPU %" | tee -a cpu.$NUMCLIENTS
    let NUM_CPUS=$NUM_CPUS+1
  done
  echo "Average CPU util: `echo $LIST_CPUS | awk -v n=$NUM_CPUS -v t=$TOTAL_CPU '{printf "%.1f",t/n}'` %"
    ;;
  Darwin)
    ;;
  esac
}

#
# Perform temporary environment changes required for testing
#
function setup() {
  case `uname` in
  Linux)
    # For Perfect, I needed to enable tcp_tw_reuse and tcp_tw_recycle
    # (this should be safe given that we are only talking over localhost)
    TCP_TW_REUSE=`cat /proc/sys/net/ipv4/tcp_tw_reuse`
    TCP_TW_RECYCLE=`cat /proc/sys/net/ipv4/tcp_tw_recycle`
    sudo su -c "echo 1 > /proc/sys/net/ipv4/tcp_tw_reuse"
    sudo su -c "echo 1 > /proc/sys/net/ipv4/tcp_tw_recycle"
    ;;
  Darwin)
    # On Mac, we have to monkey with the TCP defaults to drive load
    # (see: http://stackoverflow.com/questions/1216267)
    # Defaults are:
    # net.inet.ip.portrange.first: 49152
    # net.inet.ip.portrange.last: 65535
    # net.inet.tcp.msl: 15000
    FIRST_EPHEM_PORT=`sysctl -n net.inet.ip.portrange.first`
    LAST_EPHEM_PORT=`sysctl -n net.inet.ip.portrange.last`
    TCP_MSL=`sysctl -n net.inet.tcp.msl`
    NEW_FIRST_PORT=$FIRST_EPHEM_PORT
    NEW_TCP_MSL=$TCP_MSL
    if [ $TCP_MSL -gt 1000 ]; then
      echo "Reducing the TCP maximum segment lifetime (otherwise, we will rapidly run out of ports):"
      echo "sudo sysctl -w net.inet.tcp.msl=1000"
      sudo sysctl -w net.inet.tcp.msl=1000
      NEW_TCP_MSL=`sysctl -n net.inet.tcp.msl`
    fi
    if [ $FIRST_EPHEM_PORT -gt 16384 ]; then
      echo "Increasing number of ephemeral ports available"
      echo "sudo sysctl -w net.inet.ip.portrange.first=16384"
      sudo sysctl -w net.inet.ip.portrange.first=16384
      NEW_FIRST_PORT=`sysctl -n net.inet.ip.portrange.first`
    fi
    ;;
  esac

  # Profiling with 'oprofile', 'valgrind' and 'perf' will only work properly for 1 instance
  # of the app. 'oprofile-sys' should work with any number.
  case $PROFILER in
  perf)
    # Enable perf to access kernel address maps
    echo 0 | sudo tee /proc/sys/kernel/kptr_restrict
    PROFILER_CMD="perf record"
    ;;
  perf-cg)
    # Enable perf to access kernel address maps
    echo 0 | sudo tee /proc/sys/kernel/kptr_restrict
    PROFILER_CMD="perf record -g"
    ;;
  perf-idle)
    # Need root permissions to get scheduler stats
    PROFILER_CMD="sudo perf record -e sched:sched_stat_sleep -e sched:sched_switch -e sched:sched_process_exit -g -o perf.data.raw"
    ;;
  oprofile)
    PROFILER_CMD="operf --events CPU_CLK_UNHALTED:500000 --callgraph --vmlinux /usr/lib/debug/boot/vmlinux-`uname -r`"
    ;;
  oprofile-sys)
    PROFILER_CMD=""
    # To get kernel symbols, requires the linux-image-xyz-dbgsym package, see
    # http://superuser.com/questions/62575/where-is-vmlinux-on-my-ubuntu-installation/309589#309589
    sudo operf --events CPU_CLK_UNHALTED:500000 --callgraph --system-wide --vmlinux /usr/lib/debug/boot/vmlinux-`uname -r` &
    PROFILER_PID=$!
    ;;
  valgrind)
    let DETAILEDFREQ=$DURATION/2
    PROFILER_CMD="valgrind --tool=massif --time-unit=ms --max-snapshots=100 --detailed-freq=$DETAILEDFREQ"
    ;;
  *)
    PROFILER_CMD=""
    ;;
  esac
}

#
# Start server instance(s) and associated monitoring
#
function startup() {
  echo "Starting App ($INSTANCES instances)"
  for i in `seq 1 $INSTANCES`; do
    echo $APP_AFFINITY $APP_CMD | tee app${i}.log
    $APP_AFFINITY $PROFILER_CMD $APP_CMD >> app${i}.log 2>&1 &
    APP_PIDS="$! $APP_PIDS"
  done

  # Wait for servers to be ready (TODO: something better than 'sleep 1')
  echo "App pids=$APP_PIDS"
  sleep 1

  # monitor RSS
  let i=0
  for APP_PID in $APP_PIDS; do
    let i=$i+1
    $WORK_DIR/monitorRSS.sh $APP_PID 1 > rssout${i}.txt &
    RSSMON_PIDS="$! $RSSMON_PIDS"
  done
}

#
# Shutdown server instance(s) and associated monitoring
#
function shutdown() {
  # Shut down RSS monitoring
  kill $RSSMON_PIDS
  wait $RSSMON_PIDS
  # Shut down application
  case $PROFILER in
  perf-idle)
    # Perf was run with sudo, must kill with sudo
    sudo kill $APP_PIDS
    ;;
  oprofile)
    # Must kill operf with SIGINT, otherwise child processes are left running
    kill -SIGINT $APP_PIDS
    ;;
  oprofile-sys)
    kill $APP_PIDS
    sudo kill -SIGINT $PROFILER_PID
    wait $PROFILER_PID
    ;;
  *)
    # Standard kill (SIGTERM)
    kill $APP_PIDS
    ;;
  esac
  # Wait for process(es) to end
  wait $APP_PIDS
}

#
# Restore any temporary environment changes
#
function teardown() {
  case `uname` in
  Linux)
    sudo su -c "echo $TCP_TW_REUSE > /proc/sys/net/ipv4/tcp_tw_reuse"
    sudo su -c "echo $TCP_TW_RECYCLE > /proc/sys/net/ipv4/tcp_tw_recycle"
    ;;
  Darwin)
    if [ $TCP_MSL -ne $NEW_TCP_MSL ]; then
      echo "Restoring TCP maximum segment lifetime"
      sudo sysctl -w net.inet.tcp.msl=$TCP_MSL
    fi
    if [ $FIRST_EPHEM_PORT -ne $NEW_FIRST_PORT ]; then
      echo "Restoring ephemeral port range"
      sudo sysctl -w net.inet.ip.portrange.first=$FIRST_EPHEM_PORT
    fi
    ;;
  esac

  # Profiling output will be named with the pid of the first app instance
  FIRST_APP_PID=`echo $APP_PIDS | cut -d' ' -f1`
  case $PROFILER in
  perf)
    perf report -k /usr/lib/debug/boot/vmlinux-`uname -r` > perf-report.${FIRST_APP_PID}.txt
    cat perf-report.${FIRST_APP_PID}.txt | swift-demangle > perf-report.${FIRST_APP_PID}.demangled.txt
    ;;
  perf-cg)
    perf report --no-children -k /usr/lib/debug/boot/vmlinux-`uname -r` > perf-cg-report.${FIRST_APP_PID}.txt
    cat perf-cg-report.${FIRST_APP_PID}.txt | swift-demangle > perf-cg-report.${FIRST_APP_PID}.demangled.txt
    ;;
  perf-idle)
    sudo perf inject -v -s -i perf.data.raw -o perf.data
    sudo chown $USER: perf.data.raw perf.data
    perf report -k /usr/lib/debug/boot/vmlinux-`uname -r` > perf-idle-report.${FIRST_APP_PID}.txt
    cat perf-idle-report.${FIRST_APP_PID}.txt | swift-demangle > perf-idle-report.${FIRST_APP_PID}.demangled.txt
    ;;
  oprofile | oprofile-sys)
    # Plaintext report (overall by image, then callgraph for symbols worth 1% or more)
    opreport --demangle=none --threshold 0.1 > oprofile.${FIRST_APP_PID}.txt
    opreport --demangle=none --callgraph --threshold 1 >> oprofile.${FIRST_APP_PID}.txt 2>/dev/null
    cat oprofile.${FIRST_APP_PID}.txt | swift-demangle > oprofile.${FIRST_APP_PID}.demangled.txt
    # XML report (for use in VPA)
    opreport --xml > oprofile.${FIRST_APP_PID}.opm
    cat oprofile.${FIRST_APP_PID}.opm | swift-demangle > oprofile.${FIRST_APP_PID}.demangled.opm
    ;;
  valgrind)
    ms_print massif.out.${FIRST_APP_PID} > msprint.${FIRST_APP_PID}.txt
    cat msprint.${FIRST_APP_PID}.txt | swift-demangle > msprint.${FIRST_APP_PID}.demangled.txt
    ;;
  *)
    ;;
  esac
}

# Kills any processes started by this script and then exits
function terminate() {
  echo "Killing app: $APP_PIDS"
  # Kill process group for each app instance (syntax: -pid)
  for APP_PID in $APP_PIDS; do
    kill -- -$APP_PID
  done
  echo "Killing monitors: $RSSMON_PIDS $MPSTAT_PID"
  kill $RSSMON_PIDS
  kill $MPSTAT_PID
  echo "Processes killed"
  teardown
  exit 1
}

trap terminate SIGINT SIGQUIT SIGTERM

# Begin run
mkdir -p runs/$RUN_NAME
cd runs/$RUN_NAME

echo "Run name = '$RUN_NAME'"
echo "CPU list = '$CPULIST'"
echo "Clients sequence = '$SAMPLES'"
echo "Application: $APP_CMD"
echo "URL: $URL"

setup
startup

# Execute driver and associated monitoring for each number of clients
for SAMPLE in `echo $SAMPLES | tr ',' ' '`; do
  do_sample $SAMPLE $DURATION
done

shutdown
teardown

# Summarize RSS growth
echo "Resident set size (RSS) summary:" | tee mem.log
for i in `seq 1 $INSTANCES`; do
  RSS_START=`head -n 1 rssout${i}.txt | awk '{print $1}'`
  RSS_END=`tail -n 1 rssout${i}.txt | awk '{print $1}'`
  let RSS_DIFF=$RSS_END-$RSS_START
  echo "$i: RSS (kb): start=$RSS_START end=$RSS_END delta=$RSS_DIFF" | tee -a mem.log
done
