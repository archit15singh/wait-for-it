#!/usr/bin/env bash

# Use this script to test if a given TCP host/port are available

cmdname=${0##*/}

echoerr() {
    if [[ $QUIET -ne 1 ]]; then
        echo "$@" 1>&2
    fi
}

usage() {
    cat << USAGE >&2
Usage:
    $cmdname host:port [-s] [-t timeout] [-- command args]
    -h HOST | --host=HOST       Host or IP under test
    -p PORT | --port=PORT       TCP port under test
                                Alternatively, you specify the host and port as host:port
    -s | --strict               Only execute subcommand if the test succeeds
    -q | --quiet                Don't output any status messages
    -t TIMEOUT | --timeout=TIMEOUT
                                Timeout in seconds, zero for no timeout
    -- COMMAND ARGS             Execute command with args after the test finishes
USAGE
    exit 1
}

wait_for() {
    local start_ts=$(date +%s)

    while :; do
        if nc -z $HOST $PORT >/dev/null 2>&1; then
            local end_ts=$(date +%s)
            echoerr "$cmdname: $HOST:$PORT is available after $((end_ts - start_ts)) seconds"
            return 0
        fi

        if [[ $TIMEOUT -gt 0 && $(( $(date +%s) - start_ts )) -ge $TIMEOUT ]]; then
            echoerr "$cmdname: timeout occurred after waiting $TIMEOUT seconds for $HOST:$PORT"
            return 1
        fi

        sleep 1
    done
}

wait_for_wrapper() {
    trap "kill -INT $!" INT
    wait_for &
    wait $!
    return $?
}

# Process arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        *:*)
            IFS=':' read -r HOST PORT <<< "$1"
            shift
            ;;
        --child)
            CHILD=1
            shift
            ;;
        -q | --quiet)
            QUIET=1
            shift
            ;;
        -s | --strict)
            STRICT=1
            shift
            ;;
        -h | --host=*)
            HOST="${1#*=}"
            shift
            ;;
        -p | --port=*)
            PORT="${1#*=}"
            shift
            ;;
        -t | --timeout=*)
            TIMEOUT="${1#*=}"
            shift
            ;;
        --)
            shift
            CLI=("$@")
            break
            ;;
        --help)
            usage
            ;;
        *)
            echoerr "Unknown argument: $1"
            usage
            ;;
    esac
done

if [[ -z "$HOST" || -z "$PORT" ]]; then
    echoerr "Error: you need to provide a host and port to test."
    usage
fi

TIMEOUT=${TIMEOUT:-15}
STRICT=${STRICT:-0}
CHILD=${CHILD:-0}
QUIET=${QUIET:-0}

if [[ $CHILD -gt 0 ]]; then
    wait_for
    exit $?
else
    if [[ $TIMEOUT -gt 0 ]]; then
        wait_for_wrapper
    else
        wait_for
    fi
    RESULT=$?

    if [[ $CLI ]]; then
        if [[ $RESULT -ne 0 && $STRICT -eq 1 ]]; then
            echoerr "$cmdname: strict mode, refusing to execute subprocess"
            exit $RESULT
        fi
        exec "${CLI[@]}"
    else
        exit $RESULT
    fi
fi
