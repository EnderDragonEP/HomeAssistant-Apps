# shellcheck shell=bash
# ==============================================================================
# Fire Home Assistant events so automations can react to Mount It activity
#
#   mountit::event <type> [json]        send now (best effort, never fails)
#   mountit::event.queue <type> [json]  queue for mountit::event.flush
#   mountit::event.flush                wait for Core, then send the queue
#
# Event types are prefixed with "mountit_", e.g. mountit_drive_mounted.
# ==============================================================================

MOUNTIT_EVENT_QUEUE=/tmp/mountit_events.jsonl
MOUNTIT_CORE_API=http://supervisor/core/api

mountit::event.send() {
    local type="$1" data="$2"
    curl -sf -m 5 -o /dev/null -X POST \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$data" \
        "${MOUNTIT_CORE_API}/events/mountit_${type}"
}

mountit::event.queue() {
    local type="$1" data="${2:-}"
    [[ -n "$data" ]] || data='{}'
    jq -nc --arg t "$type" --argjson d "$data" '{"type":$t,"data":$d}' \
        >> "$MOUNTIT_EVENT_QUEUE" 2>/dev/null || true
}

mountit::event() {
    local type="$1" data="${2:-}"
    [[ -n "$data" ]] || data='{}'
    mountit::event.send "$type" "$data" \
        || bashio::log.warning "Could not deliver event mountit_${type} to Home Assistant"
    return 0
}

# Home Assistant Core may still be starting when the addon boots, so wait for
# its API (up to ~10 minutes) before sending anything queued.
mountit::event.flush() {
    local i line
    for (( i = 0; i < 60; i++ )); do
        curl -sf -m 5 -o /dev/null \
            -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
            "${MOUNTIT_CORE_API}/" && break
        sleep 10
    done

    [[ -s "$MOUNTIT_EVENT_QUEUE" ]] || return 0
    mv "$MOUNTIT_EVENT_QUEUE" "${MOUNTIT_EVENT_QUEUE}.sending"
    while IFS= read -r line; do
        mountit::event.send "$(jq -r '.type' <<< "$line")" "$(jq -c '.data' <<< "$line")" \
            || bashio::log.warning "Could not deliver event mountit_$(jq -r '.type' <<< "$line")"
    done < "${MOUNTIT_EVENT_QUEUE}.sending"
    rm -f "${MOUNTIT_EVENT_QUEUE}.sending"
}
