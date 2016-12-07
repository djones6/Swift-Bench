#!/bin/bash
# Grep the applications executed in the latest compare and re-parse without re-running

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
COMPARE="$SCRIPT_DIR/compare.sh"

# Get directory containing compare to be reprocessed.
# If not specified, try current directory
RUNNAME=$1
if [ -z "$RUNNAME" ]; then
  RUNNAME="."
fi
export RUNNAME

if [ ! -e $COMPARE ]; then
  echo "Script $COMPARE not found!"
  exit 1
fi
if [ ! -d "$RUNNAME" ]; then
  echo "Compare directory $RUNNAME not found!"
  exit 1
fi
if [ ! -e "$RUNNAME/compare_1_1.out" ]; then
  echo "$RUNNAME/compare_1_1.out not found!"
  exit 1
fi

# Establish parameters of original compare
ITERATIONS=`ls -1 $RUNNAME/compare_*_1.out | wc -l`
URL=`grep 'URL:' $RUNNAME/compare_1_1.out | cut -d' ' -f2`
CLIENT=`grep 'Client machine:' $RUNNAME/compare_1_1.out | cut -d' ' -f3`
export ITERATIONS URL CLIENT

# Pass list of applications back to compare script in recompare mode
grep 'Application:' $RUNNAME/compare_1_*.out | cut -d' ' -f2 -s | xargs env RECOMPARE=true $COMPARE
