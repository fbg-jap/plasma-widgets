#!/bin/sh
# Starts, stops or restarts one container or a whole Compose stack, for the Docker Status widget.
# Usage: action.sh <context> <start|stop|restart> <container-id>
#        action.sh <context> <start|stop|restart> --project <compose-project>
# An empty context uses docker's current context. A stack is addressed by its project name only,
# so its compose file doesn't have to be on this machine.
case "$2" in
    start|stop|restart) ;;
    *) echo "Unknown action: $2" >&2; exit 2 ;;
esac
context=$1
if [ "$3" = "--project" ]; then
    set -- compose --project-name "$4" "$2"
else
    set -- "$2" "$3"
fi
if [ -n "$context" ]; then
    exec docker --context "$context" "$@"
fi
exec docker "$@"
