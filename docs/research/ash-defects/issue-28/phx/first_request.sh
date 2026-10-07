#!/bin/bash
# usage: first_request.sh <label> <command...>   starts the server, prints the first two responses of /probe
label=$1; shift
echo "### $label"
"$@" > server.log 2>&1 &
pid=$!
ok=0
for i in $(seq 1 60); do
  if curl -sf http://127.0.0.1:4877/probe -o first.txt 2>/dev/null; then ok=1; break; fi
  perl -e 'select(undef,undef,undef,0.5)'
done
[ $ok = 1 ] && echo "request 1: $(cat first.txt)" || { echo "server did not answer"; tail -20 server.log; }
echo "request 2: $(curl -s http://127.0.0.1:4877/probe)"
kill $pid 2>/dev/null; pkill -P $pid 2>/dev/null; wait $pid 2>/dev/null
perl -e 'select(undef,undef,undef,1.5)'
