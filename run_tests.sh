#!/usr/bin/env bash
# Headless verification. Usage: GODOT=/path/to/godot ./run_tests.sh
set -e
G=${GODOT:-godot}
cd "$(dirname "$0")"
$G --headless --editor --quit --path . >/dev/null 2>&1
$G --headless --path . -- --test=menu | grep "\[test\]"
$G --headless --path . -- --test=smoke | grep "\[test\]"
$G --headless --path . -- --test=smoke2 | grep "\[test\]"
$G --headless --path . -- --test=walkcap | grep "\[test\]"
$G --headless --path . -- --test=kbtest | grep "\[test\]"
$G --headless --path . -- --test=weapons | grep "\[test\]"
for m in 0 1 2; do $G --headless --path . -- --test=mapcheck$m | grep "\[test\] \(OK\|FAIL\|mapcheck\)"; done
$G --headless --path . -- --test=smokefail | grep "\[test\]"
$G --headless --path . -- --test=server > /tmp/ds_server.log 2>&1 &
sleep 2
$G --headless --path . -- --test=client | grep "\[test\]"
wait
grep "\[test\]" /tmp/ds_server.log
$G --headless --path . -- --test=server_late > /tmp/ds_server_late.log 2>&1 &
sleep 4
$G --headless --path . -- --test=client | grep "\[test\]"
wait
grep "\[test\]" /tmp/ds_server_late.log
# room-code relay (needs node + relay deps: cd relay && npm install)
if command -v node >/dev/null && [ -d relay/node_modules ]; then
  rm -f /tmp/ds_room_code.txt
  PORT=9081 node relay/relay.js > /tmp/ds_relay.log 2>&1 &
  RELAY_PID=$!
  sleep 1
  $G --headless --path . -- --test=relay_host > /tmp/ds_relay_host.log 2>&1 &
  for i in $(seq 1 40); do [ -f /tmp/ds_room_code.txt ] && break; sleep 0.5; done
  $G --headless --path . -- --test=relay_client | grep "\[test\]"
  sleep 4
  grep "\[test\]" /tmp/ds_relay_host.log
  kill $RELAY_PID || true
fi
# dedicated WebSocket server + ws client
$G --headless --path . -- --server --port=8081 > /tmp/ds_ded.log 2>&1 &
DED_PID=$!
sleep 2
$G --headless --path . -- --test=client_ws | grep "\[test\]"
kill $DED_PID || true
# versus (team deathmatch): host kills client twice through the authoritative path, client respawns
$G --headless --path . -- --test=pvp_server > /tmp/ds_pvp_server.log 2>&1 &
sleep 2
$G --headless --path . -- --test=pvp_client | grep "\[test\]"
sleep 8
grep -a "\[test\]" /tmp/ds_pvp_server.log
