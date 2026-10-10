#!/bin/sh
# Prints {"problems": <table>, "all": <table>, "extra": <table>} from PRTG's sensor table API:
# full details for every sensor that is not Up or paused, just the status of every sensor
# (for the per-state counts), and full details for the sensors in the extra status codes
# (the other states the widget lists; an empty table when none are given).
# Usage: fetch.sh <server-url> [<comma-separated status codes>]
# The API key is read from the keyring. The widget's settings page saves it there,
# or it can be stored by hand with:
#   secret-tool store --label="PRTG API key" service plasma-prtg server <server-url>
# It is handed to curl on stdin so it never appears in the process list.
set -e

server=$1
extra_codes=$2
if [ -z "$server" ]; then
    echo "No PRTG server configured" >&2
    exit 2
fi

key=$(secret-tool lookup service plasma-prtg server "$server") || true
if [ -z "$key" ]; then
    echo "No API key in the keyring for $server" >&2
    exit 3
fi

fetch() {
    printf 'url = "%s/api/table.json?%s&apitoken=%s"\n' "$server" "$1" "$key" \
        | curl --silent --show-error --fail --max-time 30 --config -
}

# Status codes: 4 Warning, 5 Down, 10 Unusual, 13 Down (acknowledged), 14 Down (partial)
problems=$(fetch "content=sensors&count=500&columns=objid,device,sensor,status,status_raw,message_raw,lastvalue&filter_status=4&filter_status=5&filter_status=10&filter_status=13&filter_status=14")
all=$(fetch "content=sensors&count=50000&columns=objid,status_raw")

extra='{"sensors":[]}'
if [ -n "$extra_codes" ]; then
    filter=""
    for code in $(echo "$extra_codes" | tr ',' ' '); do
        case $code in
            *[!0-9]*) echo "Invalid status code: $code" >&2; exit 2 ;;
        esac
        filter="$filter&filter_status=$code"
    done
    extra=$(fetch "content=sensors&count=500&columns=objid,device,sensor,status,status_raw,message_raw,lastvalue$filter")
fi

printf '{"problems":%s,"all":%s,"extra":%s}\n' "$problems" "$all" "$extra"
