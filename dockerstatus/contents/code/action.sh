#!/bin/sh
# Starts, stops or restarts one container, for the Docker Status widget.
# Usage: action.sh <context> <start|stop|restart> <container-id>
# An empty context uses docker's current context.
case "$2" in
    start|stop|restart) ;;
    *) echo "Unknown action: $2" >&2; exit 2 ;;
esac
if [ -n "$1" ]; then
    exec docker --context "$1" "$2" "$3"
fi
exec docker "$2" "$3"
