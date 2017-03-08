#!/bin/bash
#
# Copyright IBM Corporation 2016, 2017
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
# Convenience script to generate a comparison of multiple applications.
# Each application will be run in succession, repeated a total of N times,
# and the results averaged.
#

# Determine location of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. ${SCRIPT_DIR}/lib/json_output.sh

if [ -z "$1" ]; then
  echo "Usage: ./compare.sh <impl1> ... <implN>"
  echo "Please specify fully qualified path to the application."
  echo "Optionally, set following environment variables:"
  echo "  DRIVER: workload driver (default: wrk)"
  echo "  ITERATIONS: number of repetitions of each implementation (default: 5)"
  echo "  URL: url to drive load against (default: http://127.0.0.1:8080/plaintext)"
  echo "  CLIENT: server to use to execute load driver (default: localhost)"
  echo "  CPUS: list of CPUs to affinitize to (default: 0,1,2,3)"
  echo "  CLIENTS: # of concurrent clients (default: 128)"
  echo "  DURATION: time (sec) to apply load (default: 30)"
  echo "  SLEEP: time (sec) to wait between tests (default: 5)"
  echo "  RUNNAME: name of directory to store results (default: compares/DDDDMMYY-HHmmss)"
  echo "Output control:"
  echo "  RSS_TRACE: set to enable production of periodic RSS values in CSV format"
  echo "  CPU_TRACE: set to enable periodic CPU values in CSV format"
  echo "  THROUGHPUT_TRACE: set to enable periodic throughput values in CSV format"
  echo "  CPU_STATS: set to report total/user/sys CPU time consumed by application"
  echo "  JSONFILE: fully-qualified filename to write results to in JSON format"
  echo "Instance control:"
  echo "  To run multiple instances of the application, add a comma and a number to the"
  echo "  filename, eg: /my/app,4 to run 4 instances of /my/app"
  exit 1
fi

if [ ! -z "$JSONFILE" ]; then
  json_set_file $JSONFILE
  json_start
fi

if [ -z "$ITERATIONS" ]; then
  ITERATIONS=5
  echo "Using default ITERATIONS: $ITERATIONS"
else
  echo "Using ITERATIONS: $ITERATIONS"
fi
json_number "Iterations" $ITERATIONS

if [ -z "$CPUS" ]; then
  CPUS="0,1,2,3"
  echo "Using default CPUS: $CPUS"
else
  echo "Using CPUS: $CPUS"
fi
json_string "CPU Affinity" "$CPUS"

if [ -z "$URL" ]; then
  URL="http://127.0.0.1:8080/plaintext"
  echo "Using default URL: $URL"
else
  echo "Using URL: $URL"
fi
json_string "URL" "$URL"

if [ -z "$CLIENT" ]; then
  CLIENT="localhost"
  echo "Using default CLIENT: $CLIENT"
else
  echo "Using CLIENT: $CLIENT"
fi
json_string "Client" "$CLIENT"

if [ -z "$CLIENTS" ]; then
  CLIENTS=128
  echo "Using default CLIENTS: $CLIENTS"
else
  echo "Using CLIENTS: $CLIENTS"
fi
json_number "Clients" $CLIENTS

if [ -z "$DURATION" ]; then
  DURATION=30
  echo "Using default DURATION: $DURATION"
else
  echo "Using DURATION: $DURATION"
fi
json_number "Duration" $DURATION

if [ -z "$SLEEP" ]; then
  SLEEP=5
fi

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
json_string "Run Name" "$RUNNAME"
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
json_string "Results Directory" "$PWD/$WORKDIR"

# Log environment
json_env

# Check requested applications all exist
json_object_start "Implementations"
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
    json_end
    exit 1
  fi
  let IMPLC=$IMPLC+1
  IMPLS[$IMPLC]=$impl
  INSTANCES[$IMPLC]=$instances
  echo "Implementation $IMPLC: ${IMPLS[$IMPLC]}" | tee -a $SUMMARY
  json_string "$IMPLC" "${IMPLS[$IMPLC]}"
done
json_object_end

# Create a directory to store run logs
mkdir -p $WORKDIR/runs

# Execute tests
for i in `seq 1 $ITERATIONS`; do
  json_object_start "Iteration $i"
  for j in `seq 1 $IMPLC`; do
    json_object_start "Implementation $j"
    echo "Iteration $i: Implementation $j"
    run="${i}_${j}"
    let runNo=($i-1)*$IMPLC+$j
    out="$WORKDIR/compare_$run.out"
    json_string "Output File" "$out"
    # set RECOMPARE to skip running + just re-parse output files from an earlier run
    if [ -z "$RECOMPARE" ]; then
      sleep $SLEEP  # Allow system time to settle
      # Usage: ./drive.sh <run name> <cpu list> <clients list> <duration> <app> <url> <instances>
      $SCRIPT_DIR/drive.sh compare_$run $CPUS $CLIENTS $DURATION ${IMPLS[$j]} $URL ${INSTANCES[$j]} > $out 2>&1
    else
      echo ./drive.sh compare_$run $CPUS $CLIENTS $DURATION ${IMPLS[$j]} $URL ${INSTANCES[$j]}
    fi
    json_string "Command" "./drive.sh compare_$run $CPUS $CLIENTS $DURATION ${IMPLS[$j]} $URL ${INSTANCES[$j]}"

    # Archive the results from this run
    if [ -z "$RECOMPARE" ]; then
      mv runs/compare_$run $WORKDIR/runs/
    fi

    # Don't parse output if iteration did not terminate successfully
    if grep 'Detected successful termination' $out; then
        json_string "Good iteration" "true"
    else
        echo "Ignoring iteration as did not terminate successfully"
        json_string "Good iteration" "false"
        json_object_end  # end implementation
        continue
    fi
    # Note, removal of carriage return chars (^M) required when client output comes from 'ssh -t'
    THROUGHPUT[$runNo]=`grep 'Requests/sec' $out | awk '{gsub("\\r", ""); print $2}'`
    CPU[$runNo]=`grep 'Average CPU util' $out | awk '{print $4}'`
    MEM[$runNo]=`grep 'RSS (kb)' $out | sed -e's#.*max=\([0-9][0-9]*\).*#\1#' | awk '{total += $1} END {print total}'`
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
    json_number "Avg Throughput" ${THROUGHPUT[$runNo]}
    json_number "Avg CPU" ${CPU[$runNo]}
    json_number "Peak RSS" ${MEM[$runNo]}
    json_number "Avg Latency" ${LATAVG[$runNo]}
    json_number "99% Latency" ${LAT99PCT[$runNo]}
    json_number "Max Latency" ${LATMAX[$runNo]}
    json_object_start "CSV"
    # Surface throughput trace data, if requested
    if [ ! -z "$THROUGHPUT_TRACE" ]; then
      echo -n "THROUGHPUT_TRACE: "
      case "$DRIVER" in
        wrk2|sleep)
          TRACE="Unavailable"
          ;;
        jmeter)
          TRACE=`grep 'THROUGHPUT_TRACE:' $out | sed -e's#THROUGHPUT_TRACE:##'`
          ;;
        *)
          TRACE=`cat $out | awk 'BEGIN {r=""} /requests in last/ {r=r $8 ","} END {print r}'`
      esac
      echo $TRACE
      json_string "Throughput CSV" "$TRACE"
    fi
    # Surface CPU trace data, if requested
    if [ ! -z "$CPU_TRACE" ]; then
      TRACE=`grep 'CPU_USER_TRACE' $out | sed -e's#CPU_USER_TRACE:##'`
      echo "CPU_USER_TRACE: $TRACE"
      json_string "CPU User CSV" "$TRACE"
      TRACE=`grep 'CPU_SYS_TRACE' $out | sed -e's#CPU_SYS_TRACE:##'`
      echo "CPU_SYS_TRACE: $TRACE"
      json_string "CPU Sys CSV" "$TRACE"
      TRACE=`grep 'CPU_TOTAL_TRACE' $out | sed -e's#CPU_TOTAL_TRACE:##'`
      echo "CPU_TOTAL_TRACE: $TRACE"
      json_string "CPU Total CSV" "$TRACE"
    fi
    # Surface CPU time stats, if requested (sum of instances)
    if [ ! -z "$CPU_STATS" ]; then
      let NUM_INSTANCES=`grep "CPU time delta" $out | wc -l`
      CPU_USR=0
      CPU_SYS=0
      CPU_TOT=0
      for instNum in `seq 1 ${NUM_INSTANCES}`; do
        TRACE=`grep "${instNum}: CPU time delta" $out`
        val=`echo $TRACE | sed -e's#.*user=\([0-9\.\-]*\) .*#\1#'`
        CPU_USR=$(bc <<< "$val + $CPU_USR")
        val=`echo $TRACE | sed -e's#.*sys=\([0-9\.\-]*\) .*#\1#'`
        CPU_SYS=$(bc <<< "$val + $CPU_SYS")
        val=`echo $TRACE | sed -e's#.*total=\([0-9\.\-]*\).*#\1#'`
        CPU_TOT=$(bc <<< "$val + $CPU_TOT")
      done
      echo "Total CPU time consumed by $NUM_INSTANCES server processes: user=$CPU_USR sys=$CPU_SYS total=$CPU_TOT"
      json_number "Process CPUTime User" $CPU_USR
      json_number "Process CPUTime Sys" $CPU_SYS
      json_number "Process CPUTime Total" $CPU_TOT
    fi
    # Surface RSS trace data, if requested (sum of instances)
    if [ ! -z "$RSS_TRACE" ]; then
# TODO - sum multiple instances
      TRACE=`grep 'RSS_TRACE' $out | sed -e's#.*RSS_TRACE: ##'`
      echo "RSS_TRACE: $TRACE"
      json_string "RSS CSV" "$TRACE"
    fi
    json_object_end  # end CSV
    # Record number of server processes that were summarized
    NUM_PROCESSES=`grep 'Total server processes' $out | sed -e's#Total server processes: ##'`
    json_number "Process Count" $NUM_PROCESSES
    json_object_end  # end implementation
  done
  json_object_end    # end iteration
done

# Summarize
json_object_start "Summary"
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
  json_object_start "Implementation $j"
  json_number "Avg Throughput" $AVG_TP
  json_number "Max Throughput" $MAX_TP
  json_number "Avg CPU" $AVG_CPU
  json_number "Avg Peak RSS" $AVG_MEM
  json_number "Avg Latency" $AVG_LAT
  json_number "99% Latency" $MAX99_LAT
  json_number "Max Latency" $MAX_LAT
  json_number "Good iterations" $goodIterations
  json_object_end  # End implementation
done
json_object_end    # End summary

json_end

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
