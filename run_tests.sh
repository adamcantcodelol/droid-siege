#!/usr/bin/env bash
# Headless verification. Usage: GODOT=/path/to/godot ./run_tests.sh
set -e
G=${GODOT:-godot}
cd "$(dirname "$0")"
$G --headless --editor --quit --path . >/dev/null 2>&1
$G --headless --path . -- --test=menu | grep "\[test\]"
$G --headless --path . -- --test=smoke | grep "\[test\]"
$G --headless --path . -- --test=smoke2 | grep "\[test\]"
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
