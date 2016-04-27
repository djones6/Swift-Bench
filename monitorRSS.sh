#!/bin/sh
# Simple script to capture resident set and virtual size of a process (as reported by 'ps')
# periodically, to monitor process footprint over time.

# Kitura zombie process causes problems here... an alternative (get the RSS from one of the threads)
# would be:
# ps -p <pid> -L -o pid,ppid,tid,time,rss,cmd
# or:
# ps -p <pid> -L -o rss,vsz

PID=$1
INTERVAL=$2

if [ -z "$INTERVAL" ]; then
  echo "Usage: monitorRSS <pid> <interval>"
  exit 1
fi

while true; do
  #ps -p $PID -o rss,vsz | tail -n 1
  #fix for Kitura:
  ps -p $PID -L -o rss,vsz | tail -n 1
  sleep $INTERVAL
done
