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
  echo "  ITERATIONS: number of repetitions of each implementation (default: 3)"
  echo "  URL: url to drive load against (default: http://127.0.0.1:8080/plaintext)"
  echo "  CPUS: list of CPUs to affinitize to (default: 0,1,2,3)"
  echo "  CLIENTS: # of concurrent clients (default: 128)"
  echo "  DURATION: time (sec) to apply load (default: 10)"
  exit 1
fi

if [ -z "$ITERATIONS" ]; then
  ITERATIONS=3
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
  DURATION=10
  echo "Using default DURATION: $DURATION"
else
  echo "Using DURATION: $DURATION"
fi

if [ -z "$SLEEP" ]; then
  SLEEP=5
fi

# Check requested applications all exist
let IMPLC=0
for impl in $*; do
  if [ ! -e "$impl" ]; then
    echo "Error: $impl is not executable"
    exit 1
  fi
  let IMPLC=$IMPLC+1
  IMPLS[$IMPLC]=$impl
  echo "Implementation $IMPLC: ${IMPLS[$IMPLC]}"
done

# Execute tests
for i in `seq 1 $ITERATIONS`; do
  for j in `seq 1 $IMPLC`; do
    echo "Iteration $i: Implementation $j"
    sleep $SLEEP  # Allow system time to settle
    run="${i}_${j}"
    let runNo=($i-1)*$IMPLC+$j
    out="compare_$run.out"
    # Usage: ./drive.sh <run name> <cpu list> <clients list> <duration> <app> <url> <instances>
    ./drive.sh compare_$run $CPUS $CLIENTS $DURATION ${IMPLS[$j]} $URL 1 > $out 2>&1
    THROUGHPUT[$runNo]=`grep 'Requests/sec' $out | awk '{print $2}'`
    CPU[$runNo]=`grep 'Average CPU util' $out | awk '{print $4}'`
    MEM[$runNo]=`grep 'RSS (kb)' $out | sed -e's#.*end=\([0-9]\+\).*#\1#'`
    echo "Throughput = ${THROUGHPUT[$runNo]} CPU = ${CPU[$runNo]} MEM = ${MEM[$runNo]}"
  done
done

# Summarize
echo 'Implementation | Avg Throughput | Max Throughput | Avg CPU | Avg RSS (kb) '
echo '---------------|----------------|----------------|---------|--------------'
for j in `seq 1 $IMPLC`; do
  TOT_TP=0
  TOT_CPU=0
  TOT_MEM=0
  MAX_TP=0
  for i in `seq 1 $ITERATIONS`; do
    run="${i}_${j}"
    let runNo=($i-1)*$IMPLC+$j
    TOT_TP=$(bc <<< "${THROUGHPUT[$runNo]} + $TOT_TP")
    TOT_CPU=$(bc <<< "${CPU[$runNo]} + $TOT_CPU")
    TOT_MEM=$(bc <<< "${MEM[$runNo]} + $TOT_MEM")
    if [ $(bc <<< "${THROUGHPUT[$runNo]} > $MAX_TP") = "1" ]; then
      MAX_TP=${THROUGHPUT[$runNo]}
    fi
  done
  AVG_TP=$(bc <<< "scale=1; $TOT_TP / $ITERATIONS")
  AVG_CPU=$(bc <<< "scale=1; $TOT_CPU / $ITERATIONS")
  AVG_MEM=$(bc <<< "scale=0; $TOT_MEM / $ITERATIONS")
  awk -v a="$j" -v b="$AVG_TP" -v c="$MAX_TP" -v d="$AVG_CPU" -v e="$AVG_MEM" 'BEGIN {printf "%14s | %14s | %14s | %7s | %12s \n", a, b, c, d, e}'
done
