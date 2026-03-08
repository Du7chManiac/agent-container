#!/bin/bash
MODE="${OPENCODE_MODE:-serve}"
PORT="${OPENCODE_PORT:-4096}"

case "$MODE" in
    ssh)
        ssh-keyscan -p 22 localhost >/dev/null 2>&1 || exit 1
        ;;
    *)
        curl -sf "http://localhost:${PORT}/doc" >/dev/null 2>&1 || exit 1
        ;;
esac
