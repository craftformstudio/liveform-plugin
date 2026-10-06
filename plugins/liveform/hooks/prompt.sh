#!/usr/bin/env bash
set +e
DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$DIR/run.sh" hook prompt --tool claude-code
exit $?
