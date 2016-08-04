#!/bin/bash
#
# Convenience script to generate a comparison of multiple applications.
# Each application will be run in succession, repeated a total of N times,
# and the results averaged.
#

if [ -z "$1" ]; then
  echo "Usage: ./compare.sh <impl1> ... <implN>"
  echo "Please specify fully qualified path to the application."
  echo "Optionally, set following environment variables:"
  echo "  ITERATIONS: number of repetitions of each implementation (default: 5)"
  echo "  URL: url to drive load against (default: http://127.0.0.1:8080/plaintext)"
  echo "  CPUS: list of CPUs to affinitize to (default: 0,1,2,3)"
  echo "  CLIENTS: # of concurrent clients (default: 128)"
  echo "  DURATION: time (sec) to apply load (default: 30)"
  echo "  SLEEP: time (sec) to wait between tests (default: 5)"
  echo "  RUNNAME: name of directory to store results (default: current date and time)"
  exit 1
fi

if [ -z "$ITERATIONS" ]; then
  ITERATIONS=5
  echo "Using default ITERATIONS: $ITERATIONS"
else
  echo "Using ITERATIONS: $ITERATIONS"
fi

if [ -z "$CPUS" ]; then
  CPUS="0,1,2,3"
  echo "Using default CPUS: $CPUS"
else
  echo "Using ITERATIONS: $ITERATIONS"
fi

if [ -z "$URL" ]; then
  URL="http://127.0.0.1:8080/plaintext"
  echo "Using default URL: $URL"
else
  echo "Using URL: $URL"
fi

if [ -z "$CLIENTS" ]; then
  CLIENTS=128
  echo "Using default CLIENTS: $CLIENTS"
else
  echo "Using CLIENTS: $CLIENTS"
fi

if [ -z "$DURATION" ]; then
  DURATION=30
  echo "Using default DURATION: $DURATION"
else
  echo "Using DURATION: $DURATION"
fi

if [ -z "$SLEEP" ]; then
  SLEEP=5
fi

# Define a location to store the output (default: compares/<date>-<time>)
if [ -z "$RUNNAME" ]; then
  RUNNAME=`date +'%Y%m%d-%H%M%S'`
fi
WORKDIR="compares/$RUNNAME"
echo "Results will be stored in $WORKDIR"

# Check requested applications all exist
let IMPLC=0
for implstr in $*; do
  # Parse impl string into executable,instances
  impl=`echo $implstr | cut -d',' -f1`
  instances=`echo $implstr | cut -d',' -f2 -s`
  if [ ! -e "$impl" ]; then
    echo "Error: $impl is not executable"
    exit 1
  fi
  let IMPLC=$IMPLC+1
  IMPLS[$IMPLC]=$impl
  INSTANCES[$IMPLC]=$instances
  echo "Implementation $IMPLC: ${IMPLS[$IMPLC]}"
done

# Create a directory to store run logs
mkdir -p $WORKDIR/runs

# Execute tests
for i in `seq 1 $ITERATIONS`; do
  for j in `seq 1 $IMPLC`; do
    echo "Iteration $i: Implementation $j"
    run="${i}_${j}"
    let runNo=($i-1)*$IMPLC+$j
    out="$WORKDIR/compare_$run.out"
    # set RECOMPARE to skip running + just re-parse output files from an earlier run
    if [ -z "$RECOMPARE" ]; then
      sleep $SLEEP  # Allow system time to settle
      # Usage: ./drive.sh <run name> <cpu list> <clients list> <duration> <app> <url> <instances>
      ./drive.sh compare_$run $CPUS $CLIENTS $DURATION ${IMPLS[$j]} $URL ${INSTANCES[$j]} > $out 2>&1
    else
      echo ./drive.sh compare_$run $CPUS $CLIENTS $DURATION ${IMPLS[$j]} $URL ${INSTANCES[$j]}
    fi
    THROUGHPUT[$runNo]=`grep 'Requests/sec' $out | awk '{print $2}'`
    CPU[$runNo]=`grep 'Average CPU util' $out | awk '{print $4}'`
    MEM[$runNo]=`grep 'RSS (kb)' $out | sed -e's#.*end=\([0-9][0-9]*\).*#\1#' | awk '{total += $1} END {print total}'`
    LATAVG[$runNo]=`grep 'Latency  ' $out | awk '{print $2}' | awk '/[0-9\.]+s/ { print $1 * 1000 } /[0-9\.]+ms/ { print $1 / 1 } /[0-9\.]+us/ { print $1/1000 }'`
    LATMAX[$runNo]=`grep 'Latency  ' $out | awk '{print $4}' | awk '/[0-9\.]+s/ { print $1 * 1000 } /[0-9\.]+ms/ { print $1 / 1 } /[0-9\.]+us/ { print $1/1000 }'`
    echo "Throughput = ${THROUGHPUT[$runNo]} CPU = ${CPU[$runNo]} MEM = ${MEM[$runNo]}  Latency: avg = ${LATAVG[$runNo]}ms max = ${LATMAX[$runNo]}ms"
    # Archive the results from this run
    mv runs/compare_$run $WORKDIR/runs/
  done
done

# Summarize
echo 'Implementation | Avg Throughput | Max Throughput | Avg CPU | Avg RSS (kb) | Avg Lat (ms) | Max Lat (ms) '
echo '---------------|----------------|----------------|---------|--------------|--------------|--------------'
for j in `seq 1 $IMPLC`; do
  TOT_TP=0
  TOT_CPU=0
  TOT_MEM=0
  MAX_TP=0
  TOT_LAT=0
  MAX_LAT=0
  for i in `seq 1 $ITERATIONS`; do
    run="${i}_${j}"
    let runNo=($i-1)*$IMPLC+$j
    TOT_TP=$(bc <<< "${THROUGHPUT[$runNo]} + $TOT_TP")
    TOT_CPU=$(bc <<< "${CPU[$runNo]} + $TOT_CPU")
    TOT_MEM=$(bc <<< "${MEM[$runNo]} + $TOT_MEM")
    TOT_LAT=$(bc <<< "${LATAVG[$runNo]} + $TOT_LAT")
    if [ $(bc <<< "${THROUGHPUT[$runNo]} > $MAX_TP") = "1" ]; then
      MAX_TP=${THROUGHPUT[$runNo]}
    fi
    if [ $(bc <<< "${LATMAX[$runNo]} > $MAX_LAT") = "1" ]; then
      MAX_LAT=${LATMAX[$runNo]}
    fi
  done
  AVG_TP=$(bc <<< "scale=1; $TOT_TP / $ITERATIONS")
  AVG_CPU=$(bc <<< "scale=1; $TOT_CPU / $ITERATIONS")
  AVG_MEM=$(bc <<< "scale=0; $TOT_MEM / $ITERATIONS")
  AVG_LAT=$(bc <<< "scale=1; $TOT_LAT / $ITERATIONS")
  awk -v a="$j" -v b="$AVG_TP" -v c="$MAX_TP" -v d="$AVG_CPU" -v e="$AVG_MEM" -v f="$AVG_LAT" -v g="$MAX_LAT" 'BEGIN {printf "%14s | %14s | %14s | %7s | %12s | %12s | %12s \n", a, b, c, d, e, f, g}'
done
