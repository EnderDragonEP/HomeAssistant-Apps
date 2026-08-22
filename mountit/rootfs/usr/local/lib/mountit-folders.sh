#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# Configure Samba shares for folder mounts and track their runtime state
# ==============================================================================

MOUNTIT_OPTIONS_FILE="${MOUNTIT_OPTIONS_FILE:-/data/options.json}"
MOUNTIT_MOUNTS_FILE="${MOUNTIT_MOUNTS_FILE:-/tmp/mountit_mounts.json}"
MOUNTIT_FOLDER_MOUNTS_FILE="${MOUNTIT_FOLDER_MOUNTS_FILE:-/tmp/mountit_folder_mounts.json}"
MOUNTIT_SAMBA_CONFIG="${MOUNTIT_SAMBA_CONFIG:-/etc/samba/smb.conf}"

mountit::sanitize_name() {
    printf '%s' "$1" | sed 's/[^A-Za-z0-9_]/_/g'
}

mountit::append_samba_share() {
    local share_name="$1" full_path="$2"

    if grep -Fxq "[$share_name]" "$MOUNTIT_SAMBA_CONFIG" 2>/dev/null; then
        return 0
    fi

    {
        printf '[%s]\n'                    "$share_name"
        printf '   path = %s\n'            "$full_path"
        printf '   valid users = _mountit_\n'
        printf '   read only = No\n'
        printf '   guest ok = No\n'
        printf '   force user = root\n'
        printf '   create mask = 0777\n'
        printf '   directory mask = 0777\n\n'
    } >> "$MOUNTIT_SAMBA_CONFIG"
}

mountit::remove_samba_share() {
    local share_name="$1" config_tmp=""

    [[ -f "$MOUNTIT_SAMBA_CONFIG" ]] || return 0
    grep -Fxq "[$share_name]" "$MOUNTIT_SAMBA_CONFIG" 2>/dev/null || return 0

    config_tmp=$(mktemp /tmp/mountit-smb-conf.XXXXXX) || return 1
    if ! awk -v section="$share_name" '
        $0 == "[" section "]" { skip = 1; next }
        /^\[/ { skip = 0 }
        !skip { print }
    ' "$MOUNTIT_SAMBA_CONFIG" > "$config_tmp"; then
        rm -f "$config_tmp"
        return 1
    fi
    if ! cat "$config_tmp" > "$MOUNTIT_SAMBA_CONFIG"; then
        rm -f "$config_tmp"
        return 1
    fi
    rm -f "$config_tmp"
}

mountit::add_folder_mounts_for_drive() {
    local drive_key="$1" count i configured_name drive configured_drive_key
    local folder location drive_mp full_path folder_clean share_name mount_name
    local reserved_names="media share backup config addons ssl homeassistant"

    [[ -f "$MOUNTIT_FOLDER_MOUNTS_FILE" ]] \
        || printf '{}\n' > "$MOUNTIT_FOLDER_MOUNTS_FILE" \
        || return 1
    count=$(jq '.folder_mounts | length' "$MOUNTIT_OPTIONS_FILE" 2>/dev/null || echo 0)

    for ((i = 0; i < count; i++)); do
        configured_name=$(jq -r ".folder_mounts[$i].name // empty" "$MOUNTIT_OPTIONS_FILE")
        drive=$(jq -r ".folder_mounts[$i].drive" "$MOUNTIT_OPTIONS_FILE")
        folder=$(jq -r ".folder_mounts[$i].folder" "$MOUNTIT_OPTIONS_FILE")
        location=$(jq -r ".folder_mounts[$i].location" "$MOUNTIT_OPTIONS_FILE")
        configured_drive_key=$(mountit::sanitize_name "$drive")

        [[ "$configured_drive_key" == "$drive_key" ]] || continue

        if ! jq -e --arg d "$drive_key" '.[$d]' "$MOUNTIT_MOUNTS_FILE" > /dev/null 2>&1; then
            bashio::log.error "  $drive/$folder — drive '$drive' is not mounted, skipping"
            continue
        fi

        drive_mp=$(jq -r --arg d "$drive_key" '.[$d].mount_point' "$MOUNTIT_MOUNTS_FILE")
        full_path="${drive_mp}/${folder}"
        if [[ ! -d "$full_path" ]]; then
            bashio::log.error "  $drive/$folder — path does not exist ($full_path), skipping"
            continue
        fi

        local drive_root resolved_path
        drive_root=$(readlink -f "$drive_mp" 2>/dev/null || true)
        resolved_path=$(readlink -f "$full_path" 2>/dev/null || true)
        if [[ -z "$drive_root" || -z "$resolved_path" ]] \
            || [[ "$resolved_path" != "$drive_root" && "$resolved_path" != "$drive_root/"* ]]; then
            bashio::log.error "  $drive/$folder — resolved path escapes the mounted drive, skipping"
            continue
        fi
        full_path="$resolved_path"

        folder_clean=$(printf '%s' "$folder" | sed 's|[^a-zA-Z0-9]|_|g; s|_\+|_|g; s|^_||; s|_$||')
        share_name="${drive_key}_${folder_clean}"
        mount_name="${configured_name:-$share_name}"

        if [[ ! "$mount_name" =~ ^[A-Za-z0-9_]+$ ]]; then
            bashio::log.error "  $drive/$folder — network storage name '$mount_name' is invalid, skipping"
            continue
        fi

        local reserved=false rn
        for rn in $reserved_names; do
            if [[ "${mount_name,,}" == "${rn,,}" ]]; then
                reserved=true
                break
            fi
        done
        if $reserved; then
            bashio::log.error "  $drive/$folder — network storage name '$mount_name' is reserved, skipping"
            continue
        fi

        if jq -e --arg n "$share_name" '.[$n]' "$MOUNTIT_MOUNTS_FILE" > /dev/null 2>&1; then
            bashio::log.error "  $drive/$folder — Samba share '$share_name' conflicts with a drive mount, skipping"
            continue
        fi
        if jq -e --arg n "$mount_name" '.[$n]' "$MOUNTIT_MOUNTS_FILE" > /dev/null 2>&1; then
            bashio::log.error "  $drive/$folder — network storage name '$mount_name' conflicts with a drive mount, skipping"
            continue
        fi

        if jq -e --arg n "$mount_name" '.[$n]' "$MOUNTIT_FOLDER_MOUNTS_FILE" > /dev/null 2>&1; then
            local old_share old_path
            old_share=$(jq -r --arg n "$mount_name" '.[$n].share' "$MOUNTIT_FOLDER_MOUNTS_FILE")
            old_path=$(jq -r --arg n "$mount_name" '.[$n].path' "$MOUNTIT_FOLDER_MOUNTS_FILE")
            if [[ "$old_share" == "$share_name" && "$old_path" == "$full_path" ]]; then
                mountit::append_samba_share "$share_name" "$full_path" || return 1
                continue
            fi
            bashio::log.error "  $drive/$folder — network storage name '$mount_name' conflicts with another folder mount, skipping"
            continue
        fi

        if jq -e --arg n "$share_name" '.[] | select(.share == $n)' "$MOUNTIT_FOLDER_MOUNTS_FILE" > /dev/null 2>&1; then
            bashio::log.error "  $drive/$folder — Samba share '$share_name' conflicts with another folder mount, skipping"
            continue
        fi

        if ! mountit::append_samba_share "$share_name" "$full_path"; then
            bashio::log.error "  $drive/$folder — could not create Samba share '$share_name'"
            return 1
        fi

        local state_tmp
        state_tmp=$(mktemp "${MOUNTIT_FOLDER_MOUNTS_FILE}.XXXXXX") || {
            mountit::remove_samba_share "$share_name" || true
            return 1
        }
        if jq --arg k "$mount_name" --arg share "$share_name" \
            --arg drive "$drive" --arg drive_key "$drive_key" --arg folder "$folder" \
            --arg path "$full_path" --arg loc "$location" \
            '. + {($k): {"share":$share,"drive":$drive,"drive_key":$drive_key,"folder":$folder,"path":$path,"location":$loc}}' \
            "$MOUNTIT_FOLDER_MOUNTS_FILE" > "$state_tmp" \
            && mv -f "$state_tmp" "$MOUNTIT_FOLDER_MOUNTS_FILE"; then
            :
        else
            rm -f "$state_tmp"
            mountit::remove_samba_share "$share_name" || true
            return 1
        fi

        bashio::log.green "  $drive/$folder → $mount_name [$share_name] ($location)"
    done
}

mountit::configure_all_folder_mounts() {
    local drive_key

    printf '{}\n' > "$MOUNTIT_FOLDER_MOUNTS_FILE" || return 1
    while IFS= read -r drive_key; do
        [[ -n "$drive_key" ]] || continue
        mountit::add_folder_mounts_for_drive "$drive_key" || return 1
    done < <(jq -r 'keys[]' "$MOUNTIT_MOUNTS_FILE" 2>/dev/null)
}

mountit::remove_folder_shares_for_drive() {
    local drive_key="$1" mount_name share_name state_tmp failures=0
    local -a mount_names=()

    [[ -f "$MOUNTIT_FOLDER_MOUNTS_FILE" ]] || return 0
    mapfile -t mount_names < <(jq -r --arg d "$drive_key" \
        'to_entries[] | select(.value.drive_key == $d) | .key' \
        "$MOUNTIT_FOLDER_MOUNTS_FILE" 2>/dev/null)

    for mount_name in "${mount_names[@]}"; do
        share_name=$(jq -r --arg n "$mount_name" '.[$n].share' "$MOUNTIT_FOLDER_MOUNTS_FILE")
        mountit::remove_samba_share "$share_name" || ((failures += 1))

        state_tmp=$(mktemp "${MOUNTIT_FOLDER_MOUNTS_FILE}.XXXXXX") || return 1
        if jq --arg n "$mount_name" 'del(.[$n])' \
            "$MOUNTIT_FOLDER_MOUNTS_FILE" > "$state_tmp" \
            && mv -f "$state_tmp" "$MOUNTIT_FOLDER_MOUNTS_FILE"; then
            :
        else
            rm -f "$state_tmp"
            return 1
        fi
    done

    ((failures == 0))
}
