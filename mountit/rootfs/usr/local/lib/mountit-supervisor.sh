#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# Secure, state-aware Home Assistant Supervisor mount reconciliation
# ==============================================================================

MOUNTIT_DATA_DIR="${MOUNTIT_DATA_DIR:-/data}"
MOUNTIT_RUNTIME_DIR="${MOUNTIT_RUNTIME_DIR:-/tmp}"
MOUNTIT_MOUNTS_FILE="${MOUNTIT_MOUNTS_FILE:-${MOUNTIT_RUNTIME_DIR}/mountit_mounts.json}"
MOUNTIT_FOLDER_MOUNTS_FILE="${MOUNTIT_FOLDER_MOUNTS_FILE:-${MOUNTIT_RUNTIME_DIR}/mountit_folder_mounts.json}"
MOUNTIT_REGISTERED_FILE="${MOUNTIT_REGISTERED_FILE:-${MOUNTIT_RUNTIME_DIR}/mountit_registered_mounts.json}"
MOUNTIT_MANAGED_FILE="${MOUNTIT_MANAGED_FILE:-${MOUNTIT_DATA_DIR}/mountit_managed_mounts.json}"
MOUNTIT_PASSWORD_FILE="${MOUNTIT_PASSWORD_FILE:-${MOUNTIT_DATA_DIR}/mountit_password}"
MOUNTIT_RUNTIME_PASSWORD_FILE="${MOUNTIT_RUNTIME_PASSWORD_FILE:-${MOUNTIT_RUNTIME_DIR}/mountit_password}"
MOUNTIT_SMB_AUTH_FILE="${MOUNTIT_SMB_AUTH_FILE:-${MOUNTIT_RUNTIME_DIR}/mountit_smbclient_auth}"
MOUNTIT_LOCK_FILE="${MOUNTIT_LOCK_FILE:-${MOUNTIT_RUNTIME_DIR}/mountit-supervisor.lock}"
MOUNTIT_API_BASE="${MOUNTIT_API_BASE:-${SUPERVISOR_API:-http://supervisor}}"
MOUNTIT_RETRY_DELAYS="${MOUNTIT_RETRY_DELAYS:-0 3 6 12}"
MOUNTIT_VERIFY_DELAYS="${MOUNTIT_VERIFY_DELAYS:-0 1 2 3}"
MOUNTIT_REMOVE_DELAYS="${MOUNTIT_REMOVE_DELAYS:-0 1 2 4}"
MOUNTIT_PENDING_RETRY_AGE="${MOUNTIT_PENDING_RETRY_AGE:-300}"
MOUNTIT_OPERATION_HOLDOFF="${MOUNTIT_OPERATION_HOLDOFF:-300}"
MOUNTIT_API_READ_MAX_TIME="${MOUNTIT_API_READ_MAX_TIME:-20}"
MOUNTIT_API_CREATE_MAX_TIME="${MOUNTIT_API_CREATE_MAX_TIME:-120}"
MOUNTIT_API_MUTATION_MAX_TIME="${MOUNTIT_API_MUTATION_MAX_TIME:-240}"
MOUNTIT_API_DELETE_MAX_TIME="${MOUNTIT_API_DELETE_MAX_TIME:-105}"

MOUNTIT_API_DATA='{}'
MOUNTIT_API_ERROR=''
MOUNTIT_API_STATUS=''
MOUNTIT_API_AMBIGUOUS=false
MOUNTIT_MOUNT_ENTRY=''
MOUNTIT_API_CURL_PID=''
MOUNTIT_API_BODY_FILE=''
MOUNTIT_API_RESPONSE_FILE=''

mountit::ensure_object_file() {
    local file="$1" tmp=""

    if [[ -f "$file" ]] && jq -e 'type == "object"' "$file" > /dev/null 2>&1; then
        chmod 0600 "$file" 2>/dev/null || true
        return 0
    fi

    if [[ -f "$file" ]]; then
        bashio::log.warning "Resetting invalid Mount It state: $file"
    fi
    tmp=$(mktemp "${file}.XXXXXX") || return 1
    printf '{}\n' > "$tmp" || {
        rm -f "$tmp"
        return 1
    }
    chmod 0600 "$tmp" || {
        rm -f "$tmp"
        return 1
    }
    mv -f "$tmp" "$file"
}

mountit::init_supervisor_context() {
    MOUNTIT_SERVER=$(cat "${MOUNTIT_RUNTIME_DIR}/mountit_ip" 2>/dev/null || true)
    MOUNTIT_SERVER="${MOUNTIT_SERVER/\/*/}"
    MOUNTIT_USERNAME="_mountit_"
    MOUNTIT_PASSWORD=$(cat "$MOUNTIT_RUNTIME_PASSWORD_FILE" 2>/dev/null || true)

    if [[ -z "$MOUNTIT_SERVER" || -z "$MOUNTIT_PASSWORD" ]]; then
        bashio::log.error "Mount It registration context is incomplete"
        return 1
    fi
    if [[ -z "${SUPERVISOR_TOKEN:-}" ]]; then
        bashio::log.error "Supervisor API token is unavailable"
        return 1
    fi

    # Hash the exact value sent to Supervisor. The persistent file should be
    # identical, but using the in-memory value avoids a misleading generation
    # marker if that file is changed while the app is running.
    MOUNTIT_CREDENTIAL_ID=$(printf '%s' "$MOUNTIT_PASSWORD" | sha256sum 2>/dev/null | awk '{print $1}')
    if [[ -z "$MOUNTIT_CREDENTIAL_ID" ]]; then
        bashio::log.error "Could not identify the persistent Samba credential"
        return 1
    fi

    export MOUNTIT_SERVER MOUNTIT_USERNAME MOUNTIT_CREDENTIAL_ID
    mountit::ensure_object_file "$MOUNTIT_MANAGED_FILE" || return 1
    mountit::ensure_object_file "$MOUNTIT_REGISTERED_FILE" || return 1
}

mountit::lock() {
    local wait_seconds="${1:-60}"
    if [[ -n "${MOUNTIT_LOCK_FD:-}" ]]; then
        return 0
    fi
    exec {MOUNTIT_LOCK_FD}> "$MOUNTIT_LOCK_FILE" || return 1
    if [[ "$wait_seconds" == "-1" ]]; then
        while [[ -e "/proc/$$/fd/${MOUNTIT_LOCK_FD}" ]]; do
            flock -w 5 "$MOUNTIT_LOCK_FD" && return 0
        done
    elif flock -w "$wait_seconds" "$MOUNTIT_LOCK_FD"; then
        return 0
    else
        eval "exec ${MOUNTIT_LOCK_FD}>&-"
        unset MOUNTIT_LOCK_FD
        return 1
    fi

    eval "exec ${MOUNTIT_LOCK_FD}>&-"
    unset MOUNTIT_LOCK_FD
    return 1
}

mountit::unlock() {
    [[ -n "${MOUNTIT_LOCK_FD:-}" ]] || return 0
    flock -u "$MOUNTIT_LOCK_FD" 2>/dev/null || true
    eval "exec ${MOUNTIT_LOCK_FD}>&-"
    unset MOUNTIT_LOCK_FD
}

mountit::cancel_api() {
    if [[ "${MOUNTIT_API_CURL_PID:-}" =~ ^[0-9]+$ ]]; then
        kill "$MOUNTIT_API_CURL_PID" 2>/dev/null || true
        wait "$MOUNTIT_API_CURL_PID" 2>/dev/null || true
        MOUNTIT_API_CURL_PID=''
    fi
    [[ -z "${MOUNTIT_API_BODY_FILE:-}" ]] || rm -f -- "$MOUNTIT_API_BODY_FILE"
    [[ -z "${MOUNTIT_API_RESPONSE_FILE:-}" ]] || rm -f -- "$MOUNTIT_API_RESPONSE_FILE"
    MOUNTIT_API_BODY_FILE=''
    MOUNTIT_API_RESPONSE_FILE=''
}

# Bashio versions in older base images can trace request bodies. Mount payloads
# contain the persistent Samba password, so send them through a protected file
# and pass the authorization header over stdin instead of argv.
mountit::api() {
    local method="$1" resource="$2" body="${3:-}"
    local body_file="" response_file="" response="" payload="" status="" curl_status=0
    local result="" message="" token="${SUPERVISOR_TOKEN:-}" max_time
    local mutating=false
    local -a curl_args

    MOUNTIT_API_DATA='{}'
    MOUNTIT_API_ERROR=''
    MOUNTIT_API_STATUS=''
    MOUNTIT_API_AMBIGUOUS=false
    [[ "$method" == "GET" ]] || mutating=true

    if [[ -z "$token" ]]; then
        MOUNTIT_API_ERROR="Supervisor API token is unavailable"
        return 1
    fi

    case "$method $resource" in
        "GET "*)    max_time="$MOUNTIT_API_READ_MAX_TIME" ;;
        "POST /mounts") max_time="$MOUNTIT_API_CREATE_MAX_TIME" ;;
        "DELETE "*) max_time="$MOUNTIT_API_DELETE_MAX_TIME" ;;
        *)           max_time="$MOUNTIT_API_MUTATION_MAX_TIME" ;;
    esac

    curl_args=(
        --silent --show-error
        --connect-timeout 10
        --max-time "$max_time"
        --write-out $'\n%{http_code}'
        --request "$method"
        -H @-
        -H 'Content-Type: application/json'
    )

    if [[ -n "$body" ]]; then
        body_file=$(mktemp "${MOUNTIT_RUNTIME_DIR}/mountit-api-body.XXXXXX") || {
            MOUNTIT_API_ERROR="Could not create a protected API request file"
            return 1
        }
        MOUNTIT_API_BODY_FILE="$body_file"
        if ! chmod 0600 "$body_file"; then
            rm -f "$body_file"
            MOUNTIT_API_BODY_FILE=''
            MOUNTIT_API_ERROR="Could not protect the API request file"
            return 1
        fi
        if ! printf '%s' "$body" > "$body_file"; then
            rm -f "$body_file"
            MOUNTIT_API_BODY_FILE=''
            MOUNTIT_API_ERROR="Could not prepare the API request"
            return 1
        fi
        curl_args+=(--data-binary "@$body_file")
    fi

    response_file=$(mktemp "${MOUNTIT_RUNTIME_DIR}/mountit-api-response.XXXXXX") || {
        [[ -z "$body_file" ]] || rm -f "$body_file"
        MOUNTIT_API_BODY_FILE=''
        MOUNTIT_API_ERROR="Could not create a protected API response file"
        return 1
    }
    MOUNTIT_API_RESPONSE_FILE="$response_file"
    chmod 0600 "$response_file" || {
        rm -f "$response_file"
        [[ -z "$body_file" ]] || rm -f "$body_file"
        MOUNTIT_API_BODY_FILE=''
        MOUNTIT_API_RESPONSE_FILE=''
        MOUNTIT_API_ERROR="Could not protect the API response file"
        return 1
    }
    (
        # Do not let a long-running curl child retain the operation lock if
        # the supervising shell is terminated during shutdown.
        if [[ "${MOUNTIT_LOCK_FD:-}" =~ ^[0-9]+$ ]]; then
            eval "exec ${MOUNTIT_LOCK_FD}>&-"
        fi
        exec curl "${curl_args[@]}" "${MOUNTIT_API_BASE}${resource}" \
            <<< "Authorization: Bearer ${token}"
    ) > "$response_file" &
    MOUNTIT_API_CURL_PID=$!
    if wait "$MOUNTIT_API_CURL_PID"; then
        curl_status=0
    else
        curl_status=$?
    fi
    MOUNTIT_API_CURL_PID=''
    response=$(< "$response_file")
    rm -f "$response_file"
    MOUNTIT_API_RESPONSE_FILE=''
    [[ -z "$body_file" ]] || rm -f "$body_file"
    MOUNTIT_API_BODY_FILE=''

    if ((curl_status != 0)); then
        # Once curl connected, a transport error or timeout does not prove the
        # Supervisor discarded the mutation. Callers must re-read live state
        # before deciding whether another mutation is safe.
        [[ "$curl_status" != "6" && "$curl_status" != "7" ]] \
            && MOUNTIT_API_AMBIGUOUS=true
        MOUNTIT_API_ERROR="Supervisor API request failed (curl $curl_status)"
        return 1
    fi

    status="${response##*$'\n'}"
    payload="${response%$'\n'*}"
    MOUNTIT_API_STATUS="$status"

    if [[ ! "$status" =~ ^[0-9]{3}$ ]] || ! jq -e . > /dev/null 2>&1 <<< "$payload"; then
        $mutating && MOUNTIT_API_AMBIGUOUS=true
        MOUNTIT_API_ERROR="Supervisor API returned an invalid response"
        return 1
    fi

    result=$(jq -r '.result // empty' <<< "$payload")
    message=$(jq -r '.message // empty' <<< "$payload" | tr '\r\n' ' ' | head -c 300)
    if [[ -n "${MOUNTIT_PASSWORD:-}" ]]; then
        message="${message//$MOUNTIT_PASSWORD/[redacted]}"
    fi
    if [[ "$status" != "200" || "$result" != "ok" ]]; then
        if $mutating && [[ "$status" =~ ^5[0-9]{2}$ ]]; then
            MOUNTIT_API_AMBIGUOUS=true
        fi
        MOUNTIT_API_ERROR="${message:-Supervisor API returned HTTP $status}"
        return 1
    fi

    MOUNTIT_API_DATA=$(jq -c '.data // {}' <<< "$payload")
}

mountit::get_mount() {
    local name="$1"

    MOUNTIT_MOUNT_ENTRY=''
    if ! mountit::api GET /mounts; then
        return 1
    fi
    if ! jq -e '.mounts | type == "array"' > /dev/null 2>&1 <<< "$MOUNTIT_API_DATA"; then
        MOUNTIT_API_ERROR="Supervisor returned an invalid mounts list"
        return 1
    fi

    MOUNTIT_MOUNT_ENTRY=$(jq -c --arg n "$name" \
        'first(.mounts[]? | select(.name == $n)) // empty' \
        <<< "$MOUNTIT_API_DATA")
}

mountit::entry_matches_identity() {
    local entry="$1" server="$2" share="$3"
    jq -e --arg server "$server" --arg share "$share" \
        '.type == "cifs" and .server == $server and .share == $share' \
        > /dev/null 2>&1 <<< "$entry"
}

mountit::entry_matches_config() {
    local entry="$1" server="$2" share="$3" usage="$4"
    jq -e --arg server "$server" --arg share "$share" --arg usage "$usage" \
        '.type == "cifs" and .server == $server and .share == $share and
         .usage == $usage and ((.read_only // false) == false)' \
        > /dev/null 2>&1 <<< "$entry"
}

mountit::manifest_entry() {
    local name="$1"
    jq -c --arg n "$name" '.[$n] // empty' "$MOUNTIT_MANAGED_FILE" 2>/dev/null
}

mountit::manifest_owns_entry() {
    local name="$1" live_entry="$2" managed_entry
    managed_entry=$(mountit::manifest_entry "$name")
    [[ -n "$managed_entry" ]] || return 1

    jq -e --argjson live "$live_entry" '
        .type == "cifs" and $live.type == "cifs" and
        ((.server == $live.server and .share == $live.share) or
         (.pending == true and .previous_server == $live.server and
          .previous_share == $live.share))
    ' > /dev/null 2>&1 <<< "$managed_entry"
}

mountit::credential_is_synced() {
    local name="$1"
    jq -e --arg n "$name" --arg id "$MOUNTIT_CREDENTIAL_ID" \
        '.[$n].credential_id == $id' "$MOUNTIT_MANAGED_FILE" > /dev/null 2>&1
}

mountit::pending_matches() {
    local name="$1" share="$2" usage="$3"
    jq -e --arg n "$name" --arg server "$MOUNTIT_SERVER" --arg share "$share" \
        --arg usage "$usage" --arg id "$MOUNTIT_CREDENTIAL_ID" '
        .[$n].pending == true and .[$n].server == $server and
        .[$n].share == $share and .[$n].usage == $usage and
        .[$n].credential_id == $id
    ' "$MOUNTIT_MANAGED_FILE" > /dev/null 2>&1
}

mountit::pending_is_recent() {
    local name="$1" acknowledged_at now age
    acknowledged_at=$(jq -r --arg n "$name" '.[$n].acknowledged_at // 0' \
        "$MOUNTIT_MANAGED_FILE" 2>/dev/null)
    [[ "$acknowledged_at" =~ ^[0-9]+$ ]] || return 1
    now=$(date +%s)
    age=$((now - acknowledged_at))
    ((age >= 0 && age < MOUNTIT_PENDING_RETRY_AGE))
}

mountit::manifest_operation() {
    local name="$1"
    jq -r --arg n "$name" '.[$n].operation // empty' \
        "$MOUNTIT_MANAGED_FILE" 2>/dev/null
}

mountit::operation_is_recent() {
    local name="$1" started_at now age
    started_at=$(jq -r --arg n "$name" '.[$n].operation_started_at // 0' \
        "$MOUNTIT_MANAGED_FILE" 2>/dev/null)
    [[ "$started_at" =~ ^[0-9]+$ ]] || return 1
    now=$(date +%s)
    age=$((now - started_at))
    ((age >= 0 && age < MOUNTIT_OPERATION_HOLDOFF))
}

# Write intent before contacting Supervisor. If the process or HTTP connection
# dies after sending the request, later passes can wait out the Supervisor job
# window instead of submitting a competing mutation.
mountit::record_operation_intent() {
    local name="$1" operation="$2" server="$3" share="$4"
    local usage="${5:-}" kind="${6:-}" drive="${7:-}" started_at tmp=""

    started_at=$(date +%s)
    tmp=$(mktemp "${MOUNTIT_MANAGED_FILE}.XXXXXX") || return 1
    if jq --arg name "$name" --arg operation "$operation" --arg server "$server" \
        --arg share "$share" --arg usage "$usage" --arg kind "$kind" --arg drive "$drive" \
        --arg credential_id "$MOUNTIT_CREDENTIAL_ID" --arg at "$started_at" '
        .[$name] = ((.[$name] // {
            "type":"cifs","server":$server,"share":$share,"usage":$usage,
            "kind":$kind,"drive":$drive
        }) + {
            "operation":$operation,"operation_started_at":($at | tonumber),
            "operation_server":$server,"operation_share":$share,
            "operation_usage":$usage,"operation_credential_id":$credential_id
        })
    ' "$MOUNTIT_MANAGED_FILE" > "$tmp" \
        && chmod 0600 "$tmp" \
        && mv -f "$tmp" "$MOUNTIT_MANAGED_FILE"; then
        return 0
    fi
    rm -f "$tmp"
    return 1
}

mountit::clear_operation_intent() {
    local name="$1" tmp=""
    tmp=$(mktemp "${MOUNTIT_MANAGED_FILE}.XXXXXX") || return 1
    if jq --arg n "$name" '
        del(.[$n].operation, .[$n].operation_started_at,
            .[$n].operation_server, .[$n].operation_share,
            .[$n].operation_usage, .[$n].operation_credential_id)
    ' "$MOUNTIT_MANAGED_FILE" > "$tmp" \
        && chmod 0600 "$tmp" \
        && mv -f "$tmp" "$MOUNTIT_MANAGED_FILE"; then
        return 0
    fi
    rm -f "$tmp"
    return 1
}

# Keep ownership identity after a verified removal, but discard transient
# create/update/delete markers so a deliberate restart can recreate at once.
mountit::mark_removed() {
    local name="$1" tmp=""
    tmp=$(mktemp "${MOUNTIT_MANAGED_FILE}.XXXXXX") || return 1
    if jq --arg n "$name" '
        del(.[$n].pending, .[$n].acknowledged_at,
            .[$n].previous_server, .[$n].previous_share,
            .[$n].operation, .[$n].operation_started_at,
            .[$n].operation_server, .[$n].operation_share,
            .[$n].operation_usage, .[$n].operation_credential_id)
    ' "$MOUNTIT_MANAGED_FILE" > "$tmp" \
        && chmod 0600 "$tmp" \
        && mv -f "$tmp" "$MOUNTIT_MANAGED_FILE"; then
        mountit::forget_registered "$name" || true
        return 0
    fi
    rm -f "$tmp"
    return 1
}

mountit::write_state_entry() {
    local file="$1" name="$2" share="$3" usage="$4" kind="$5" drive="$6"
    local tmp=""

    tmp=$(mktemp "${file}.XXXXXX") || return 1
    if jq --arg name "$name" --arg server "$MOUNTIT_SERVER" --arg share "$share" \
        --arg usage "$usage" --arg kind "$kind" --arg drive "$drive" \
        --arg credential_id "$MOUNTIT_CREDENTIAL_ID" \
        '. + {($name): {"type":"cifs","server":$server,"share":$share,
             "usage":$usage,"kind":$kind,"drive":$drive,"credential_id":$credential_id}}' \
        "$file" > "$tmp" \
        && chmod 0600 "$tmp" \
        && mv -f "$tmp" "$file"; then
        return 0
    else
        rm -f "$tmp"
        return 1
    fi
}

mountit::record_registered() {
    local name="$1" share="$2" usage="$3" kind="$4" drive="$5"
    mountit::write_state_entry "$MOUNTIT_MANAGED_FILE" "$name" "$share" "$usage" "$kind" "$drive" || return 1
    mountit::write_state_entry "$MOUNTIT_REGISTERED_FILE" "$name" "$share" "$usage" "$kind" "$drive"
}

# A definitive API success means Supervisor accepted the credential-bearing
# mutation even if the follow-up GET is temporarily unavailable. Persist that
# acknowledgement separately from runtime-active state so another pass does
# not immediately repeat a POST/PUT. Previous identity is retained solely to
# recognize a stale read while a successful configuration update settles.
mountit::record_pending() {
    local name="$1" share="$2" usage="$3" kind="$4" drive="$5" previous_entry="${6:-}"
    local previous_server="" previous_share="" acknowledged_at tmp=""

    if [[ -n "$previous_entry" ]]; then
        previous_server=$(jq -r '.server // empty' <<< "$previous_entry")
        previous_share=$(jq -r '.share // empty' <<< "$previous_entry")
    fi
    acknowledged_at=$(date +%s)
    tmp=$(mktemp "${MOUNTIT_MANAGED_FILE}.XXXXXX") || return 1
    if jq --arg name "$name" --arg server "$MOUNTIT_SERVER" --arg share "$share" \
        --arg usage "$usage" --arg kind "$kind" --arg drive "$drive" \
        --arg credential_id "$MOUNTIT_CREDENTIAL_ID" --arg at "$acknowledged_at" \
        --arg previous_server "$previous_server" --arg previous_share "$previous_share" '
        . + {($name): {
            "type":"cifs","server":$server,"share":$share,"usage":$usage,
            "kind":$kind,"drive":$drive,"credential_id":$credential_id,
            "pending":true,"acknowledged_at":($at | tonumber),
            "previous_server":$previous_server,"previous_share":$previous_share
        }}
    ' "$MOUNTIT_MANAGED_FILE" > "$tmp" \
        && chmod 0600 "$tmp" \
        && mv -f "$tmp" "$MOUNTIT_MANAGED_FILE"; then
        return 0
    else
        rm -f "$tmp"
        return 1
    fi
}

mountit::forget_state_entry() {
    local file="$1" name="$2" tmp=""
    [[ -f "$file" ]] || return 0
    tmp=$(mktemp "${file}.XXXXXX") || return 1
    if jq --arg n "$name" 'del(.[$n])' "$file" > "$tmp" \
        && chmod 0600 "$tmp" \
        && mv -f "$tmp" "$file"; then
        return 0
    else
        rm -f "$tmp"
        return 1
    fi
}

mountit::forget_registered() {
    mountit::forget_state_entry "$MOUNTIT_REGISTERED_FILE" "$1"
}

mountit::forget_managed() {
    mountit::forget_state_entry "$MOUNTIT_MANAGED_FILE" "$1"
}

mountit::mark_credential_unsynced() {
    local name="$1" tmp=""
    tmp=$(mktemp "${MOUNTIT_MANAGED_FILE}.XXXXXX") || return 1
    if jq --arg n "$name" '
        if has($n) then
            del(.[$n].credential_id, .[$n].pending, .[$n].acknowledged_at,
                .[$n].previous_server, .[$n].previous_share,
                .[$n].operation, .[$n].operation_started_at,
                .[$n].operation_server, .[$n].operation_share,
                .[$n].operation_usage, .[$n].operation_credential_id)
        else . end
    ' "$MOUNTIT_MANAGED_FILE" > "$tmp" \
        && chmod 0600 "$tmp" \
        && mv -f "$tmp" "$MOUNTIT_MANAGED_FILE"; then
        return 0
    fi
    rm -f "$tmp"
    return 1
}

mountit::probe_share() {
    local share="$1"
    (
        if [[ "${MOUNTIT_LOCK_FD:-}" =~ ^[0-9]+$ ]]; then
            eval "exec ${MOUNTIT_LOCK_FD}>&-"
        fi
        exec timeout 15 smbclient "//${MOUNTIT_SERVER}/${share}" \
            --authentication-file="$MOUNTIT_SMB_AUTH_FILE" \
            --max-protocol=SMB3 --command='quit'
    ) > /dev/null 2>&1
}

mountit::build_create_payload() {
    local name="$1" share="$2" usage="$3"
    printf '%s' "$MOUNTIT_PASSWORD" | jq -Rsc \
        --arg name "$name" --arg share "$share" --arg server "$MOUNTIT_SERVER" \
        --arg username "$MOUNTIT_USERNAME" --arg usage "$usage" \
        '{name:$name,type:"cifs",server:$server,share:$share,username:$username,password:.,usage:$usage}'
}

mountit::build_update_payload() {
    local share="$1" usage="$2"
    printf '%s' "$MOUNTIT_PASSWORD" | jq -Rsc \
        --arg share "$share" --arg server "$MOUNTIT_SERVER" \
        --arg username "$MOUNTIT_USERNAME" --arg usage "$usage" \
        '{type:"cifs",server:$server,share:$share,username:$username,password:.,usage:$usage}'
}

mountit::verify_mount_active() {
    local name="$1" share="$2" usage="$3" delay entry state

    for delay in $MOUNTIT_VERIFY_DELAYS; do
        ((delay == 0)) || sleep "$delay"
        mountit::get_mount "$name" || continue
        entry="$MOUNTIT_MOUNT_ENTRY"
        [[ -n "$entry" ]] || continue
        mountit::entry_matches_config "$entry" "$MOUNTIT_SERVER" "$share" "$usage" || return 2
        state=$(jq -r '.state // empty' <<< "$entry")
        [[ "$state" == "active" ]] && return 0
    done
    return 1
}

mountit::reconcile_mount() {
    local name="$1" share="$2" usage="$3" kind="$4" drive="$5" quiet="${6:-false}"
    local delay entry state payload action operation force_update=false
    local mutation_succeeded=false pending=false

    for delay in $MOUNTIT_RETRY_DELAYS; do
        ((delay == 0)) || sleep "$delay"

        if ! mountit::probe_share "$share"; then
            $quiet || bashio::log.warning "  $name — Samba share is not ready"
            continue
        fi

        if ! mountit::get_mount "$name"; then
            bashio::log.warning "  $name — could not inspect HA storage: $MOUNTIT_API_ERROR"
            continue
        fi
        entry="$MOUNTIT_MOUNT_ENTRY"
        pending=false
        mountit::pending_matches "$name" "$share" "$usage" && pending=true
        operation=$(mountit::manifest_operation "$name")

        if [[ -n "$operation" ]] && mountit::operation_is_recent "$name"; then
            if [[ "$operation" == "delete" && -z "$entry" ]]; then
                # Supervisor no longer tracks the completed removal. Clear its
                # transient marker so a normal restart/replug can recreate now.
                mountit::mark_removed "$name" || return 1
                operation=""
                pending=false
            elif [[ -n "$entry" ]] \
                && mountit::entry_matches_config "$entry" "$MOUNTIT_SERVER" "$share" "$usage" \
                && [[ "$(jq -r '.state // empty' <<< "$entry")" == "active" ]] \
                && { [[ "$operation" == "create" ]] \
                    || { [[ "$operation" == "reload" ]] && mountit::credential_is_synced "$name"; }; }; then
                mountit::record_registered "$name" "$share" "$usage" "$kind" "$drive" || return 1
                $quiet || bashio::log.green "  $name → $usage (active after interrupted $operation)"
                return 0
            else
                $quiet || bashio::log.info "  $name — previous HA $operation may still be running; waiting"
                continue
            fi
        fi

        if [[ -n "$entry" ]]; then
            state=$(jq -r '.state // empty' <<< "$entry")
            if [[ "$state" =~ ^(activating|deactivating|reloading)$ ]]; then
                $quiet || bashio::log.info "  $name — HA storage is $state; waiting"
                continue
            fi
        fi

        if [[ -z "$entry" ]]; then
            if $pending && mountit::pending_is_recent "$name"; then
                $quiet || bashio::log.info "  $name — accepted HA change is awaiting visibility"
                continue
            fi
            action="create"
        elif mountit::entry_matches_identity "$entry" "$MOUNTIT_SERVER" "$share"; then
            if $pending \
                && ! mountit::entry_matches_config "$entry" "$MOUNTIT_SERVER" "$share" "$usage" \
                && mountit::pending_is_recent "$name"; then
                $quiet || bashio::log.info "  $name — accepted HA update is still settling"
                continue
            fi
            if ! mountit::entry_matches_config "$entry" "$MOUNTIT_SERVER" "$share" "$usage" \
                || ! mountit::credential_is_synced "$name" || $force_update; then
                action="update"
            elif [[ "$state" == "active" ]]; then
                mountit::record_registered "$name" "$share" "$usage" "$kind" "$drive" || return 1
                $quiet || bashio::log.green "  $name → $usage (active)"
                return 0
            else
                action="reload"
            fi
        elif mountit::manifest_owns_entry "$name" "$entry"; then
            # The live entry still matches Mount It's previous manifest, so a
            # changed server/share is an owned configuration update.
            if $pending && mountit::pending_is_recent "$name"; then
                $quiet || bashio::log.info "  $name — accepted HA update is still settling"
                continue
            fi
            action="update"
        else
            bashio::log.error "  $name — name is already used by another network storage entry"
            mountit::forget_registered "$name" || true
            return 2
        fi

        case "$action" in
            create)
                mutation_succeeded=false
                payload=$(mountit::build_create_payload "$name" "$share" "$usage") || return 1
                mountit::record_operation_intent "$name" create "$MOUNTIT_SERVER" "$share" \
                    "$usage" "$kind" "$drive" || return 1
                $quiet || bashio::log.info "  $name — creating HA storage"
                if mountit::api POST /mounts "$payload"; then
                    mutation_succeeded=true
                    if ! mountit::record_pending "$name" "$share" "$usage" "$kind" "$drive"; then
                        bashio::log.error "  $name — could not record the accepted HA change"
                        if mountit::verify_mount_active "$name" "$share" "$usage"; then
                            mountit::record_registered "$name" "$share" "$usage" "$kind" "$drive" || return 1
                            bashio::log.green "  $name → $usage"
                            return 0
                        fi
                        return 1
                    fi
                else
                    bashio::log.warning "  $name — create failed: $MOUNTIT_API_ERROR"
                    if $MOUNTIT_API_AMBIGUOUS; then
                        if mountit::verify_mount_active "$name" "$share" "$usage"; then
                            mountit::record_registered "$name" "$share" "$usage" "$kind" "$drive" || return 1
                            bashio::log.green "  $name → $usage"
                            return 0
                        fi
                        bashio::log.warning "  $name — create outcome is uncertain; deferring another mutation"
                        mountit::forget_registered "$name" || true
                        return 1
                    fi
                    mountit::clear_operation_intent "$name" || return 1
                fi
                ;;
            update)
                mutation_succeeded=false
                payload=$(mountit::build_update_payload "$share" "$usage") || return 1
                mountit::record_operation_intent "$name" update "$MOUNTIT_SERVER" "$share" \
                    "$usage" "$kind" "$drive" || return 1
                $quiet || bashio::log.info "  $name — refreshing HA storage"
                if mountit::api PUT "/mounts/${name}" "$payload"; then
                    mutation_succeeded=true
                    force_update=false
                    if ! mountit::record_pending "$name" "$share" "$usage" "$kind" "$drive" "$entry"; then
                        bashio::log.error "  $name — could not record the accepted HA change"
                        if mountit::verify_mount_active "$name" "$share" "$usage"; then
                            mountit::record_registered "$name" "$share" "$usage" "$kind" "$drive" || return 1
                            bashio::log.green "  $name → $usage"
                            return 0
                        fi
                        return 1
                    fi
                else
                    bashio::log.warning "  $name — update failed: $MOUNTIT_API_ERROR"
                    if $MOUNTIT_API_AMBIGUOUS; then
                        bashio::log.warning "  $name — update outcome is uncertain; deferring another mutation"
                        mountit::forget_registered "$name" || true
                        return 1
                    fi
                    mountit::clear_operation_intent "$name" || return 1
                fi
                ;;
            reload)
                mutation_succeeded=false
                mountit::record_operation_intent "$name" reload "$MOUNTIT_SERVER" "$share" \
                    "$usage" "$kind" "$drive" || return 1
                $quiet || bashio::log.info "  $name — reloading failed HA storage"
                if mountit::api POST "/mounts/${name}/reload" '{}'; then
                    mutation_succeeded=true
                    mountit::record_pending "$name" "$share" "$usage" "$kind" "$drive" "$entry" \
                        || bashio::log.warning "  $name — could not record the accepted HA reload"
                else
                    bashio::log.warning "  $name — reload failed: $MOUNTIT_API_ERROR"
                    if $MOUNTIT_API_AMBIGUOUS; then
                        bashio::log.warning "  $name — reload outcome is uncertain; deferring another mutation"
                        mountit::forget_registered "$name" || true
                        return 1
                    fi
                    # A failed reload cannot recreate a missing Supervisor
                    # credential file. Supply the current credential via PUT.
                    if ! mountit::mark_credential_unsynced "$name"; then
                        bashio::log.warning "  $name — could not persist the required credential refresh"
                        return 1
                    fi
                    force_update=true
                    # Do not let a stale or cached active state overwrite the
                    # unsynced marker. A later retry must send the credential
                    # through PUT before this entry is considered recovered.
                    continue
                fi
                ;;
        esac

        # A failed PUT can leave the old unit active with its old credential.
        # Never mark the new credential generation synced unless PUT succeeded.
        if [[ "$action" == "update" ]] && ! $mutation_succeeded; then
            continue
        fi

        if mountit::verify_mount_active "$name" "$share" "$usage"; then
            mountit::record_registered "$name" "$share" "$usage" "$kind" "$drive" || return 1
            bashio::log.green "  $name → $usage"
            return 0
        fi
    done

    bashio::log.error "  $name — HA registration remains unavailable; background recovery will retry"
    mountit::forget_registered "$name" || true
    return 1
}

mountit::is_desired() {
    local name="$1"
    jq -e --arg n "$name" 'has($n)' "$MOUNTIT_MOUNTS_FILE" > /dev/null 2>&1 \
        || jq -e --arg n "$name" 'has($n)' "$MOUNTIT_FOLDER_MOUNTS_FILE" > /dev/null 2>&1
}

mountit::remove_mount() {
    local name="$1" expected_server="$2" expected_share="$3" quiet="${4:-false}"
    local delay entry state operation delete_ambiguous=false

    for delay in $MOUNTIT_REMOVE_DELAYS; do
        ((delay == 0)) || sleep "$delay"
        if ! mountit::get_mount "$name"; then
            bashio::log.warning "  $name — could not inspect HA storage during removal: $MOUNTIT_API_ERROR"
            continue
        fi
        entry="$MOUNTIT_MOUNT_ENTRY"
        if [[ -z "$entry" ]]; then
            operation=$(mountit::manifest_operation "$name")
            if [[ -n "$operation" && "$operation" != "delete" ]] \
                && mountit::operation_is_recent "$name"; then
                $quiet || bashio::log.info "  $name — previous HA $operation may still be running; deferring removal"
                return 1
            fi
            mountit::mark_removed "$name" || return 1
            $quiet || bashio::log.info "  $name — already removed from HA"
            return 0
        fi
        if ! mountit::entry_matches_identity "$entry" "$expected_server" "$expected_share"; then
            bashio::log.warning "  $name — HA entry no longer matches Mount It; leaving it untouched"
            mountit::forget_registered "$name" || true
            return 2
        fi

        state=$(jq -r '.state // empty' <<< "$entry")
        if [[ "$state" =~ ^(activating|deactivating|reloading)$ ]]; then
            $quiet || bashio::log.info "  $name — HA storage is $state; waiting before removal"
            continue
        fi

        operation=$(mountit::manifest_operation "$name")
        if [[ -n "$operation" ]] && mountit::operation_is_recent "$name"; then
            $quiet || bashio::log.info "  $name — previous HA $operation may still be running; deferring removal"
            return 1
        fi

        mountit::record_operation_intent "$name" delete "$expected_server" "$expected_share" \
            "" "" "" || return 1

        if mountit::api DELETE "/mounts/${name}"; then
            $quiet || bashio::log.info "  $name — removal requested"
            if mountit::get_mount "$name" && [[ -z "$MOUNTIT_MOUNT_ENTRY" ]]; then
                mountit::mark_removed "$name" || return 1
                return 0
            fi
            # A definitive success already started/completed the teardown.
            # Never submit a second DELETE merely because the confirming read
            # is stale or temporarily unavailable.
            bashio::log.warning "  $name — removal was accepted but is not yet verifiably absent"
            return 1
        else
            bashio::log.warning "  $name — removal failed: $MOUNTIT_API_ERROR"
            delete_ambiguous=$MOUNTIT_API_AMBIGUOUS
            if mountit::get_mount "$name" && [[ -z "$MOUNTIT_MOUNT_ENTRY" ]]; then
                mountit::mark_removed "$name" || return 1
                return 0
            fi
            if $delete_ambiguous; then
                bashio::log.warning "  $name — removal outcome is uncertain; deferring another DELETE"
            else
                bashio::log.warning "  $name — removal may have partially changed Supervisor state; deferring another DELETE"
            fi
            return 1
        fi
    done

    if mountit::get_mount "$name" && [[ -z "$MOUNTIT_MOUNT_ENTRY" ]]; then
        operation=$(mountit::manifest_operation "$name")
        if [[ -n "$operation" && "$operation" != "delete" ]] \
            && mountit::operation_is_recent "$name"; then
            bashio::log.warning "  $name — previous HA $operation may still be running; removal remains deferred"
            return 1
        fi
        mountit::mark_removed "$name" || return 1
        return 0
    fi
    bashio::log.warning "  $name — HA removal could not be verified"
    return 1
}

mountit::prune_managed_mounts() {
    local quiet="${1:-false}" name entry server share previous_server previous_share
    local remove_status kind failures=0
    local -a names=()

    for kind in folder drive other; do
        if [[ "$kind" == "other" ]]; then
            # Crash-safe DELETE intent can be the first persistent record for
            # an entry, before its folder/drive metadata was confirmed.
            mapfile -t names < <(jq -r '
                to_entries[] |
                select(.value.kind != "folder" and .value.kind != "drive") |
                .key
            ' "$MOUNTIT_MANAGED_FILE" 2>/dev/null)
        else
            mapfile -t names < <(jq -r --arg kind "$kind" \
                'to_entries[] | select(.value.kind == $kind) | .key' \
                "$MOUNTIT_MANAGED_FILE" 2>/dev/null)
        fi
        for name in "${names[@]}"; do
            mountit::is_desired "$name" && continue
            entry=$(mountit::manifest_entry "$name")
            server=$(jq -r '.server' <<< "$entry")
            share=$(jq -r '.share' <<< "$entry")
            $quiet || bashio::log.info "  $name — removing obsolete managed storage"
            if mountit::remove_mount "$name" "$server" "$share" "$quiet"; then
                remove_status=0
            else
                remove_status=$?
            fi
            if ((remove_status == 2)); then
                previous_server=$(jq -r '.previous_server // empty' <<< "$entry")
                previous_share=$(jq -r '.previous_share // empty' <<< "$entry")
                if [[ -n "$previous_server" && -n "$previous_share" ]]; then
                    if mountit::remove_mount "$name" "$previous_server" "$previous_share" "$quiet"; then
                        remove_status=0
                    else
                        remove_status=$?
                    fi
                fi
            fi
            if ((remove_status == 0 || remove_status == 2)); then
                mountit::forget_managed "$name" || true
            else
                ((failures += 1))
            fi
        done
    done

    ((failures == 0))
}

mountit::reconcile_all() {
    local quiet="${1:-false}" usage name share location drive failures=0 total=0

    usage=$(bashio::config 'mount_location')
    local prune_status=0
    mountit::prune_managed_mounts "$quiet" || prune_status=1

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        ((total += 1))
        mountit::reconcile_mount "$name" "$name" "$usage" drive "$name" "$quiet" || ((failures += 1))
    done < <(jq -r 'keys[]' "$MOUNTIT_MOUNTS_FILE" 2>/dev/null)

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        share=$(jq -r --arg n "$name" '.[$n].share' "$MOUNTIT_FOLDER_MOUNTS_FILE")
        location=$(jq -r --arg n "$name" '.[$n].location' "$MOUNTIT_FOLDER_MOUNTS_FILE")
        drive=$(jq -r --arg n "$name" '.[$n].drive_key // .[$n].drive' "$MOUNTIT_FOLDER_MOUNTS_FILE")
        ((total += 1))
        mountit::reconcile_mount "$name" "$share" "$location" folder "$drive" "$quiet" || ((failures += 1))
    done < <(jq -r 'keys[]' "$MOUNTIT_FOLDER_MOUNTS_FILE" 2>/dev/null)

    MOUNTIT_RECONCILE_TOTAL=$total
    MOUNTIT_RECONCILE_FAILURES=$failures
    export MOUNTIT_RECONCILE_TOTAL MOUNTIT_RECONCILE_FAILURES
    ((failures == 0 && prune_status == 0))
}
