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
WORK_DIR=$PWD
APP_CMD=$5
URL=$6

DRIVER_AFFINITY="numactl --cpunodebind=1 --membind=1"
APP_AFFINITY="numactl --physcpubind=$CPULIST --membind=0"

# Consume cmdline args (simplest possible implementation for now)
if [ -z "$1" -o "$1" == "--help" ]; then
  echo "Usage: $0 <run name> <cpu list> <clients list> <duration> <app> <url>"
  echo " - eg: $0 my_run_4way 0,1,2,3 1,5,10,100,200 30 ~/kitura http://127.0.0.1/hello"
  echo "  cpu list = comma-separated list of CPUs to affinitize to"
  echo "  client list = comma-separated list of # clients to drive load"
  echo "  duration = length of each load period (seconds)"
  echo "  app = app command to execute"
  echo "  url = URL to drive load against"
  exit 1
fi
# CPU list
if [ -z "$2" ]; then
  CPULIST="0,1,2,3"
  echo "CPU list not specified; using default of '$CPULIST'"
fi
# Clients list
if [ -z "$3" ]; then
  SAMPLES="100"
  echo "Clients list not specified; using default of '$SAMPLES'"
fi
# Duration
if [ -z "$4" ]; then
  DURATION=30
  echo "Duration not specified; using default of '$DURATION'"
fi
# App
if [ -z "$5" ]; then
  APP_CMD="./kitura"
  echo "App not specified, using default of '$APP_CMD'"
fi
# URL
if [ -z "$6" ]; then
  URL="http://127.0.0.1/json"
  echo "URL not specified, using default of '$URL'"
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
  
  # Start mpstat to monitor per-CPU utilization
  #
  mpstat -P $CPULIST 5 > mpstat.$NUMCLIENTS &
  MPSTAT_PID=$!

  # Collect information about process threads
  # (disabled for now)
  #$WORK_DIR/ps_tids.sh $APP_PID 5 > ps_tids.$NUMCLIENTS &
  #PS_PID=$!
  
  # Capture CPU cycles consumed by server before we apply load
  PRE_CPU=(`getcputime $APP_PID`)

  # Execute driver
  echo $DRIVER_AFFINITY ${WORK_DIR}/wrk -t16 -c${NUMCLIENTS} -d${DURATION}s ${URL}
  $DRIVER_AFFINITY ${WORK_DIR}/wrk -t16 -c${NUMCLIENTS} -d${DURATION}s ${URL} 2>&1 | tee results.$NUMCLIENTS
  
  # Diff CPU cycles after load applied
  POST_CPU=(`getcputime $APP_PID`)
  usec=$(bc <<< "${POST_CPU[1]} - ${PRE_CPU[1]}")
  ssec=$(bc <<< "${POST_CPU[2]} - ${PRE_CPU[2]}")
  totalsec=$(bc <<< "${POST_CPU[3]} - ${PRE_CPU[3]}")
  echo "CPU time delta: user=$usec sys=$ssec total=$totalsec"

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
  for CPU in `echo $CPULIST | tr ',' ' '`; do
    NUM_CYCLES=`cat mpstat.$NUMCLIENTS | grep -e"..:..:.. \+${CPU}" | wc -l`
    AVG_CPU=`cat mpstat.$NUMCLIENTS | grep -e"..:..:.. \+${CPU}" | awk -v SAMPLES=${NUM_CYCLES} '{TOTAL = TOTAL + (100 - $12) } END {printf "%.1f",TOTAL/SAMPLES}'`
    echo "CPU $CPU: $AVG_CPU %"
  done
  #kill $PS_PID
  #wait $PS_PID 2>/dev/null
  # Post-process PS output (TODO)
}

# Begin run
mkdir "$RUN_NAME"
cd "$RUN_NAME"

echo "Run name = '$RUN_NAME'"
echo "CPU list = '$CPULIST'"
echo "Clients sequence = '$SAMPLES'"
echo "Application: $APP_CMD"
echo "URL: $URL"

# Start server 
echo "Starting App"
echo $APP_AFFINITY $APP_CMD
$APP_AFFINITY $APP_CMD > app.log 2>&1 &
APP_PID=$!

echo "App pid=$APP_PID"
sleep 1

# Execute driver and associated monitoring for each number of clients
for SAMPLE in `echo $SAMPLES | tr ',' ' '`; do
  do_sample $SAMPLE $DURATION
done

# Shut down
echo "Killing App"
kill $APP_PID
