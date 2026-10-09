#!/bin/sh
# Prints {"problems": <table>, "all": <table>} from PRTG's sensor table API:
# full details for every sensor that is not Up or paused, and just the status of every sensor
# (for the per-state counts).
# Usage: fetch.sh <server-url>
# The API key is read from the keyring. The widget's settings page saves it there,
# or it can be stored by hand with:
#   secret-tool store --label="PRTG API key" service plasma-prtg server <server-url>
# It is handed to curl on stdin so it never appears in the process list.
set -e

server=$1
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

printf '{"problems":%s,"all":%s}\n' "$problems" "$all"
