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
  echo "  CLIENT: server to use to execute load driver (default: localhost)"
  echo "  CPUS: list of CPUs to affinitize to (default: 0,1,2,3)"
  echo "  CLIENTS: # of concurrent clients (default: 128)"
  echo "  DURATION: time (sec) to apply load (default: 30)"
  echo "  SLEEP: time (sec) to wait between tests (default: 5)"
  echo "  RUNNAME: name of directory to store results (default: compares/DDDDMMYY-HHmmss)"
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

if [ -z "$CLIENT" ]; then
  CLIENT="localhost"
  echo "Using default CLIENT: $CLIENT"
else
  echo "Using CLIENT: $CLIENT"
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

# Determine location of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check driver script is present
if [ ! -e "$SCRIPT_DIR/drive.sh" ]; then
  echo "Error: cannot find drive.sh in expected location: $SCRIPT_DIR"
  exit 1
fi
if [ ! -x "$SCRIPT_DIR/drive.sh" ]; then
  echo "Error: drive.sh script is not executable"
  exit 1
fi

# Define a location to store the output (default: compares/<date>-<time>)
if [ -z "$RUNNAME" ]; then
  RUNNAME="compares/`date +'%Y%m%d-%H%M%S'`"
fi
WORKDIR="$RUNNAME"
mkdir -p $WORKDIR
if [ $? -ne 0 ]; then
  echo "Error: Unable to create $WORKDIR"
  exit 1
else
  echo "Results will be stored in $WORKDIR"
fi

# Create a summary output file
if [ -z "$RECOMPARE" ]; then
  SUMMARY="$WORKDIR/results.txt"
else
  SUMMARY="$WORKDIR/results.txt.new"
fi
date > $SUMMARY
echo "ITERATIONS: $ITERATIONS, DURATION: $DURATION, CLIENT: '$CLIENT', CLIENTS: $CLIENTS, URL: '$URL', CPUS: '$CPUS'" >> $SUMMARY
echo "PWD: $PWD" >> $SUMMARY

# Check requested applications all exist
let IMPLC=0
for implstr in $*; do
  # Parse impl string into executable,instances
  impl=`echo $implstr | cut -d',' -f1`
  instances=`echo $implstr | cut -d',' -f2 -s`
  if [ -x "$PWD/$impl" ]; then
    impl="$PWD/$impl"  # Convert to absolute path
  fi
  if [ ! -x "$impl" -a -z "$RECOMPARE" ]; then
    echo "Error: $impl is not executable"
    exit 1
  fi
  let IMPLC=$IMPLC+1
  IMPLS[$IMPLC]=$impl
  INSTANCES[$IMPLC]=$instances
  echo "Implementation $IMPLC: ${IMPLS[$IMPLC]}" | tee -a $SUMMARY
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
      $SCRIPT_DIR/drive.sh compare_$run $CPUS $CLIENTS $DURATION ${IMPLS[$j]} $URL ${INSTANCES[$j]} > $out 2>&1
    else
      echo ./drive.sh compare_$run $CPUS $CLIENTS $DURATION ${IMPLS[$j]} $URL ${INSTANCES[$j]}
    fi
    # Note, removal of carriage return chars (^M) required when client output comes from 'ssh -t'
    THROUGHPUT[$runNo]=`grep 'Requests/sec' $out | awk '{gsub("\\r", ""); print $2}'`
    CPU[$runNo]=`grep 'Average CPU util' $out | awk '{print $4}'`
    MEM[$runNo]=`grep 'RSS (kb)' $out | sed -e's#.*end=\([0-9][0-9]*\).*#\1#' | awk '{total += $1} END {print total}'`
    LATAVG[$runNo]=`grep 'Latency  ' $out | awk '{print $2}' | awk '/[0-9\.]+s/ { print $1 * 1000 } /[0-9\.]+ms/ { print $1 / 1 } /[0-9\.]+us/ { print $1/1000 }'`
    case "$DRIVER" in
      wrk2) LAT99PCT[$runNo]=`grep ' 99.000% ' $out | awk '{print $2}' | awk '/[0-9\.]+s/ { print $1 * 1000 } /[0-9\.]+ms/ { print $1 / 1 } /[0-9\.]+us/ { print $1/1000 }'`
        ;;
      jmeter|sleep) LAT99PCT[$runNo]=0
        ;;
      *) LAT99PCT[$runNo]=`grep '     99% ' $out | awk '{print $2}' | awk '/[0-9\.]+s/ { print $1 * 1000 } /[0-9\.]+ms/ { print $1 / 1 } /[0-9\.]+us/ { print $1/1000 }'`
    esac
    LATMAX[$runNo]=`grep 'Latency  ' $out | awk '{print $4}' | awk '/[0-9\.]+s/ { print $1 * 1000 } /[0-9\.]+ms/ { print $1 / 1 } /[0-9\.]+us/ { print $1/1000 }'`
    echo "Throughput = ${THROUGHPUT[$runNo]} CPU = ${CPU[$runNo]} MEM = ${MEM[$runNo]}  Latency: avg = ${LATAVG[$runNo]}ms  99% = ${LAT99PCT[$runNo]}ms  max = ${LATMAX[$runNo]}ms"
    # Also surface throughput trace data, if requests
    if [ ! -z "$THROUGHPUT_TRACE" ]; then
       echo -n "THROUGHPUT_TRACE: "
       cat $out | awk 'BEGIN {r=""} /requests in last/ {r=r $8 ","} END {print r}'
    fi
    # Also surface RSS trace data, if requested
    if [ ! -z "$RSS_TRACE" ]; then
      grep 'RSS_TRACE' $out
    fi
    # Also surface CPU time stats, if requested
    if [ ! -z "$CPU_STATS" ]; then
      grep 'CPU time delta' $out
    fi
    # Archive the results from this run
    if [ -z "$RECOMPARE" ]; then
      mv runs/compare_$run $WORKDIR/runs/
    fi
  done
done

# Summarize
let ERRORS=0
echo '               | Throughput (req/s)      | CPU (%) | Mem (kb)     | Latency (ms)                   | good  ' >> $SUMMARY
echo 'Implementation | Average    | Max        | Average | Avg peak RSS | Average  | 99%      | Max      | iters ' >> $SUMMARY
echo '---------------|------------|------------|---------|--------------|----------|----------|----------|-------' >> $SUMMARY
for j in `seq 1 $IMPLC`; do
  TOT_TP=0
  TOT_CPU=0
  TOT_MEM=0
  MAX_TP=0
  TOT_LAT=0
  MAX99_LAT=0
  MAX_LAT=0
  let goodIterations=0
  for i in `seq 1 $ITERATIONS`; do
    run="${i}_${j}"
    let runNo=($i-1)*$IMPLC+$j
    # Check that the current run was parsed successfully
    if [[ -z "${THROUGHPUT[$runNo]}" || -z "${CPU[$runNo]}" || -z "${MEM[$runNo]}" || -z "${LATAVG[$runNo]}" || -z "${LATMAX[$runNo]}" ]]; then
        echo "Error - unable to parse data for implementation $j iteration $i"
        let ERRORS=$ERRORS+1
        continue
    fi
    # Continue processing - calculate summary statistics
    let goodIterations=$goodIterations+1
    TOT_TP=$(bc <<< "${THROUGHPUT[$runNo]} + $TOT_TP")
    TOT_CPU=$(bc <<< "${CPU[$runNo]} + $TOT_CPU")
    TOT_MEM=$(bc <<< "${MEM[$runNo]} + $TOT_MEM")
    TOT_LAT=$(bc <<< "${LATAVG[$runNo]} + $TOT_LAT")
    if [ $(bc <<< "${THROUGHPUT[$runNo]} > $MAX_TP") = "1" ]; then
      MAX_TP=${THROUGHPUT[$runNo]}
    fi
    if [ $(bc <<< "${LAT99PCT[$runNo]} > $MAX99_LAT") = "1" ]; then
      MAX99_LAT=${LAT99PCT[$runNo]}
    fi
    if [ $(bc <<< "${LATMAX[$runNo]} > $MAX_LAT") = "1" ]; then
      MAX_LAT=${LATMAX[$runNo]}
    fi
  done
  AVG_TP=$(bc <<< "scale=1; $TOT_TP / $goodIterations")
  MAX_TP=$(bc <<< "scale=1; $MAX_TP / 1")
  AVG_CPU=$(bc <<< "scale=1; $TOT_CPU / $goodIterations")
  AVG_MEM=$(bc <<< "scale=0; $TOT_MEM / $goodIterations")
  AVG_LAT=$(bc <<< "scale=1; $TOT_LAT / $goodIterations")
  MAX99_LAT=$(bc <<< "scale=1; $MAX99_LAT / 1")
  MAX_LAT=$(bc <<< "scale=1; $MAX_LAT / 1")
  awk -v a="$j" -v b="$AVG_TP" -v c="$MAX_TP" -v d="$AVG_CPU" -v e="$AVG_MEM" -v f="$AVG_LAT" -v g="$MAX99_LAT" -v h="$MAX_LAT" -v i="$goodIterations" 'BEGIN {printf "%14s | %10s | %10s | %7s | %12s | %8s | %8s | %8s | %5s \n", a, b, c, d, e, f, g, h, i}' >> $SUMMARY
done

echo "" >> $SUMMARY
if [[ $ERRORS > 0 ]]; then
  echo "*** Errors encountered during processing: $ERRORS" >> $SUMMARY
else
  echo "*** Completed successfully"
fi

# Output summary table
cat $SUMMARY

# Exit with non-zero RC if there were processing errors
exit $ERRORS
