#!/usr/bin/env bash

export ROOTDIR="$PWD"
export ENVDIR="$ROOTDIR/.kd"
export LOCAL_CONFIG="$ROOTDIR/.kd.toml"
export RUNDIR="$ENVDIR/share"
export LOG_FILE="$RUNDIR/execution_$(date +"%Y-%m-%d_%H-%M").log"

function eecho() {
  echo "$1" | tee -a $LOG_FILE
}

rm -rf "$RUNDIR/results"
rm -rf "$RUNDIR/script.sh"
mkdir -p $RUNDIR
mkdir -p $RUNDIR/results

if [ -f "$LOCAL_CONFIG" ]; then
  cp "$LOCAL_CONFIG" "$RUNDIR/kd.toml"

  if ! tq --file $LOCAL_CONFIG . > /dev/null; then
    echo "Invalid $LOCAL_CONFIG"
    exit 1
  fi

  if tq --file $LOCAL_CONFIG 'script' > /dev/null; then
    export SCRIPT_TEST="$(tq --file $LOCAL_CONFIG 'script.script')"
  fi

  if [[ -f "$SCRIPT_TEST" ]]; then
    eecho "$SCRIPT_TEST will be used as simple test"
    cp "$SCRIPT_TEST" "$RUNDIR/script.sh"
  fi
fi

export NIX_DISK_IMAGE="$ENVDIR/image.qcow2"
# After this line nix will insert more bash code. Don't exit
# TODO this has to be proper name
$NIXOS_QEMU/bin/run-*-vm 2>&1 | tee -a $LOG_FILE
echo "View results at $RUNDIR/results"
echo "Log is in $LOG_FILE"
