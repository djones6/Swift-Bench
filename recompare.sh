#!/bin/sh
# Grep the applications executed in the latest compare and re-parse without re-running

grep 'Application:' compare_1_*.out | cut -d' ' -f2 -s | xargs env RECOMPARE=true ./compare.sh
