# shellcheck shell=bash
# ==============================================================================
# Network storage, Samba share and folder mount helpers shared by the services
#
# A network storage entry belongs to Mount It only when its server is this
# addon's Samba address. Entries created by the user (for example a NAS that
# happens to share a drive's name) are never replaced or removed.
# ==============================================================================

# Print who owns network storage entry <name>: "none", "mountit" or "other"
mountit::mount.owner() {
    local name="$1" entry
    entry=$(bashio::api.supervisor GET /mounts 2>/dev/null \
        | jq -c --arg n "$name" '.mounts[]? | select(.name==$n)' 2>/dev/null | head -1)
    if [[ -z "$entry" ]]; then
        echo none
    elif [[ "$(jq -r '.server // empty' <<< "$entry")" == "$(cat /tmp/mountit_ip 2>/dev/null)" ]]; then
        echo mountit
    else
        echo other
    fi
}

# Register <name> as CIFS network storage for Samba share <share> in <usage>.
# A stale entry from a previous run is replaced; returns 1 on failure.
mountit::mount.register() {
    local name="$1" share="$2" usage="$3" cmd rt

    case "$(mountit::mount.owner "$name")" in
        other)
            bashio::log.error "  $name — name is already used by another network storage entry, skipping"
            return 1 ;;
        mountit)
            bashio::log.info "  $name — removing stale entry"
            bashio::api.supervisor DELETE "/mounts/${name}" > /dev/null 2>&1 || true
            sleep 1 ;;
    esac

    cmd=$(jq -nc \
        --arg name "$name" --arg share "$share" \
        --arg ip "$(cat /tmp/mountit_ip 2>/dev/null)" --arg user "_mountit_" \
        --arg pwd "$(cat /tmp/mountit_password 2>/dev/null)" --arg usage "$usage" \
        '{"name":$name,"type":"cifs","server":$ip,"share":$share,"username":$user,"password":$pwd,"usage":$usage}')

    for rt in 1 2 3; do
        bashio::api.supervisor POST /mounts "$cmd" > /dev/null && return 0
        bashio::log.warning "  $name — attempt $rt/3 failed, retrying..."
        sleep 3
    done
    bashio::log.error "  $name — failed to register after 3 attempts"
    return 1
}

# Remove network storage entry <name>, but only if Mount It created it
mountit::mount.deregister() {
    local name="$1"
    [[ "$(mountit::mount.owner "$name")" == "mountit" ]] || return 0
    bashio::api.supervisor DELETE "/mounts/${name}" > /dev/null 2>&1 \
        || bashio::log.warning "  $name — could not remove network storage entry"
}

# Append Samba share [<name>] for <path> to smb.conf (caller reloads smbd)
mountit::samba.add_share() {
    local name="$1" path="$2"
    {
        printf '[%s]\n'                    "$name"
        printf '   path = %s\n'            "$path"
        printf '   valid users = _mountit_\n'
        printf '   read only = No\n'
        printf '   guest ok = No\n'
        printf '   force user = root\n'
        printf '   create mask = 0777\n'
        printf '   directory mask = 0777\n\n'
    } >> /etc/samba/smb.conf
}

# Remove Samba share [<name>] from smb.conf (caller reloads smbd)
mountit::samba.remove_share() {
    python3 - "$1" << 'PYEOF'
import sys, re
label = sys.argv[1]
with open('/etc/samba/smb.conf', 'r') as f:
    content = f.read()
content = re.sub(rf'^\[{re.escape(label)}\][^\[]*', '', content, flags=re.M)
with open('/etc/samba/smb.conf', 'w') as f:
    f.write(content)
PYEOF
}

# Set up the configured folder mounts: add their Samba shares and record them
# in /tmp/mountit_folder_mounts.json. With <drive_key>, only folder mounts on
# that drive are set up (used on hot-plug). Names of the folder mounts added
# are left in MOUNTIT_NEW_FOLDERS for the caller to register.
mountit::folders.setup() {
    local only_drive="${1:-}"
    local reserved_names="media share backup config addons ssl homeassistant"
    local i count configured_name drive folder location drive_key drive_mp full_path
    local folder_clean share_name mount_name rn

    MOUNTIT_NEW_FOLDERS=()
    count=$(jq '.folder_mounts | length' /data/options.json 2>/dev/null || echo "0")

    for (( i = 0; i < count; i++ )); do
        configured_name=$(jq -r ".folder_mounts[$i].name // empty" /data/options.json)
        drive=$(jq -r ".folder_mounts[$i].drive"    /data/options.json)
        folder=$(jq -r ".folder_mounts[$i].folder"  /data/options.json)
        location=$(jq -r ".folder_mounts[$i].location" /data/options.json)

        # Mount keys are sanitized to ^[A-Za-z0-9_]+$; accept the raw label too
        drive_key=$(printf '%s' "$drive" | sed 's/[^A-Za-z0-9_]/_/g')
        [[ -n "$only_drive" && "$drive_key" != "$only_drive" ]] && continue

        # Drive must be mounted
        if ! jq -e --arg d "$drive_key" '.[$d]' /tmp/mountit_mounts.json > /dev/null 2>&1; then
            bashio::log.error "  $drive/$folder — drive '$drive' is not mounted, skipping"
            continue
        fi

        drive_mp=$(jq -r --arg d "$drive_key" '.[$d].mount_point' /tmp/mountit_mounts.json)
        full_path="${drive_mp}/${folder}"

        # Folder must exist
        if [[ ! -d "$full_path" ]]; then
            bashio::log.error "  $drive/$folder — path does not exist ($full_path), skipping"
            continue
        fi

        # Auto-generate Samba share name: drive_sanitized_folder
        folder_clean=$(echo "$folder" | sed 's|[^a-zA-Z0-9]|_|g; s|_\+|_|g; s|^_||; s|_$||')
        share_name="${drive_key}_${folder_clean}"
        mount_name="${configured_name:-$share_name}"

        # HA Supervisor mount names may contain only letters, numbers, and underscores
        if [[ ! "$mount_name" =~ ^[A-Za-z0-9_]+$ ]]; then
            bashio::log.error "  $drive/$folder — network storage name '$mount_name' is invalid, skipping"
            continue
        fi

        # Reserved name check
        for rn in $reserved_names; do
            if [[ "${mount_name,,}" == "${rn,,}" ]]; then
                bashio::log.error "  $drive/$folder — network storage name '$mount_name' is reserved, skipping"
                continue 2
            fi
        done

        # The Samba share must not conflict with an existing drive share
        if jq -e --arg n "$share_name" '.[$n]' /tmp/mountit_mounts.json > /dev/null 2>&1; then
            bashio::log.error "  $drive/$folder — Samba share '$share_name' conflicts with a drive mount, skipping"
            continue
        fi

        # The HA mount name must not conflict with an existing drive mount
        if jq -e --arg n "$mount_name" '.[$n]' /tmp/mountit_mounts.json > /dev/null 2>&1; then
            bashio::log.error "  $drive/$folder — network storage name '$mount_name' conflicts with a drive mount, skipping"
            continue
        fi

        # The HA mount name must be unique across folder mounts
        if jq -e --arg n "$mount_name" '.[$n]' /tmp/mountit_folder_mounts.json > /dev/null 2>&1; then
            bashio::log.error "  $drive/$folder — network storage name '$mount_name' conflicts with another folder mount, skipping"
            continue
        fi

        # The generated Samba share must also be unique across folder mounts
        if jq -e --arg n "$share_name" '.[] | select(.share == $n)' /tmp/mountit_folder_mounts.json > /dev/null 2>&1; then
            bashio::log.error "  $drive/$folder — Samba share '$share_name' conflicts with another folder mount, skipping"
            continue
        fi

        mountit::samba.add_share "$share_name" "$full_path"

        # Track in state
        jq --arg k "$mount_name" --arg share "$share_name" \
           --arg drive "$drive" --arg dk "$drive_key" --arg folder "$folder" \
           --arg path "$full_path" --arg loc "$location" \
           '. + {($k): {"share":$share,"drive":$drive,"drive_key":$dk,"folder":$folder,"path":$path,"location":$loc}}' \
           /tmp/mountit_folder_mounts.json > /tmp/mountit_folder_mounts.json.tmp \
        && mv /tmp/mountit_folder_mounts.json.tmp /tmp/mountit_folder_mounts.json

        MOUNTIT_NEW_FOLDERS+=("$mount_name")
        bashio::log.green "  $drive/$folder → $mount_name [$share_name] ($location)"
    done
}

# Remove the folder mounts on drive <drive_key>: network storage entry, Samba
# share and state (caller reloads smbd)
mountit::folders.teardown() {
    local drive_key="$1" mount_name share_name

    while IFS= read -r mount_name; do
        [[ -z "$mount_name" ]] && continue
        share_name=$(jq -r --arg n "$mount_name" '.[$n].share' /tmp/mountit_folder_mounts.json)
        mountit::mount.deregister "$mount_name"
        mountit::samba.remove_share "$share_name"
        jq --arg k "$mount_name" 'del(.[$k])' \
            /tmp/mountit_folder_mounts.json > /tmp/mountit_folder_mounts.json.tmp \
        && mv /tmp/mountit_folder_mounts.json.tmp /tmp/mountit_folder_mounts.json
        bashio::log.info "  $mount_name — folder mount removed"
    done < <(jq -r --arg d "$drive_key" \
        'to_entries[] | select(.value.drive_key==$d) | .key' \
        /tmp/mountit_folder_mounts.json 2>/dev/null)
}
