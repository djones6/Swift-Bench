#!/bin/sh
# Grep the applications executed in the latest compare and re-parse without re-running

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
COMPARE="$SCRIPT_DIR/compare.sh"
export RUNNAME="$1"
if [ ! -e $COMPARE ]; then
  echo "Script $COMPARE not found!"
  exit 1
fi
if [ ! -d "compares/$RUNNAME" ]; then
  echo "Compare directory compares/$RUNNAME not found!"
  exit 1
fi
grep 'Application:' compares/$RUNNAME/compare_1_*.out | cut -d' ' -f2 -s | xargs env RECOMPARE=true $COMPARE
