#!/bin/bash
MODE="${OPENCODE_MODE:-serve}"
PORT="${OPENCODE_PORT:-4096}"

case "$MODE" in
    ssh)
        ssh-keyscan -p 22 localhost >/dev/null 2>&1 || exit 1
        ;;
    openchamber)
        # Accept any HTTP response (including 401 when UI password is set)
        # since we only need to verify the server is listening.
        curl -s -o /dev/null "http://localhost:${PORT}/" || exit 1
        ;;
    *)
        # Accept any HTTP response (including 401 when OPENCODE_SERVER_PASSWORD
        # is set) since we only need to verify the server is listening.
        curl -s -o /dev/null "http://localhost:${PORT}/doc" || exit 1
        ;;
esac
