#!/bin/bash
# author: David Jones (djones6)
#
# Driver script to measure Kitura throughput and response time using JMeter.
# To use this, you need:
# 1) JMeter installed, and bin/jmeter symlinked to ./jmeter
# 2) Java installed and on your path, so that jmeter can find it
# 3) A Kitura application built, and symlinked to ./kitura
# 4) An appropriate JMeter driver script for the app, symlinked to ./driver.jmx
# 5) The 'mpstat' utility installed (if you want per-core CPU utilisation)
# 6) The 'numactl' utility installed (to control process affinity)
#
# Customize this script for your machine. I'm running on a 2-socket machine,
# with Kitura running on the first socket and JMeter running on the second.
# Change the args to numactl below so they make sense for your system.
#
# The JMeter user.properties specify a 6-second summarizer interval. When
# opening 

RUN_NAME=$1
CPULIST=$2
SAMPLES=$3
DURATION=$4
WORK_DIR=$PWD
APP_CMD=$5

JMETER_AFFINITY="numactl --cpunodebind=1 --membind=1"
KITURA_AFFINITY="numactl --physcpubind=$CPULIST --membind=0"

# Consume cmdline args (simplest possible implementation for now)
if [ -z "$1" -o "$1" == "--help" ]; then
  echo "Usage: $0 <run name> <cpu list> <clients list> <duration> <app>"
  echo " - eg: $0 my_run_4way 0,1,2,3 1,5,10,100,200 30 ~/kitura"
  echo "  cpu list = comma-separated list of CPUs to affinitize to"
  echo "  client list = comma-separated list of # clients to drive load"
  echo "  duration = length of each load period (seconds)"
  echo "  app = app command to execute"
#  echo "Symlink the Kitura app to ./kitura"
  echo "Symlink the JMeter driver script to ./driver.jmx"
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

# Measures the Kitura server using a specified number of clients + duration.
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
  #$WORK_DIR/ps_tids.sh $KITURA_PID 5 > ps_tids.$NUMCLIENTS &
  #PS_PID=$!
  
  # Capture CPU cycles consumed by Kitura before we apply load
  PRE_CPU=(`getcputime $KITURA_PID`)

  # Execute JMeter
  echo $JMETER_AFFINITY $WORK_DIR/jmeter -n -t $WORK_DIR/driver.jmx -q $WORK_DIR/user.properties -JTHREADS=$NUMCLIENTS -JDURATION=$DURATION -JRAMPUP=0 -JWARMUP=0
  $JMETER_AFFINITY $WORK_DIR/jmeter -n -t $WORK_DIR/driver.jmx -q $WORK_DIR/user.properties -JTHREADS=$NUMCLIENTS -JDURATION=$DURATION -JRAMPUP=0 -JWARMUP=0 > results.$NUMCLIENTS
  
  # Diff CPU cycles after load applied
  POST_CPU=(`getcputime $KITURA_PID`)
  usec=$(bc <<< "${POST_CPU[1]} - ${PRE_CPU[1]}")
  ssec=$(bc <<< "${POST_CPU[2]} - ${PRE_CPU[2]}")
  totalsec=$(bc <<< "${POST_CPU[3]} - ${PRE_CPU[3]}")
  echo "CPU time delta: user=$usec sys=$ssec total=$totalsec"

  # Cherry-pick useful information from JMeter summary
  SUMMARY=`grep 'summary +' results.$NUMCLIENTS | tail -n 4 | head -n 3`
  #echo $SUMMARY
  #grep 'summary =' results.$NUMCLIENTS | tail -n 1
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
echo "Driver: `ls -l $WORK_DIR/driver.jmx | sed -e's#.*-> ##'`"

# Start Kitura
echo "Starting App"
echo $KITURA_AFFINITY $APP_CMD
$KITURA_AFFINITY $APP_CMD > kitura.log 2>&1 &
KITURA_PID=$!

echo "App pid=$KITURA_PID"
sleep 1

# Execute JMeter and associated monitoring for each number of clients
for SAMPLE in `echo $SAMPLES | tr ',' ' '`; do
  do_sample $SAMPLE $DURATION
done

# Shut down
echo "Killing App"
kill $KITURA_PID
