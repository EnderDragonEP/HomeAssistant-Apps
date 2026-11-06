# shellcheck shell=bash
# ==============================================================================
# Network storage, Samba share and folder mount helpers shared by the services
#
# A network storage entry belongs to Mount It only when its server is this
# addon's Samba address. Entries created by the user (for example a NAS that
# happens to share a drive's name) are never replaced or removed.
# ==============================================================================

# True if <device> is a Home Assistant OS partition. HAOS names its GPT
# partitions hassos-*, but its system images (hassos-system0/1) carry no
# filesystem label, so checking the label alone lets them through.
mountit::is_haos_partition() {
    local partlabel
    partlabel=$(lsblk -dno PARTLABEL "$1" 2>/dev/null || true)
    [[ "$partlabel" == hassos* ]]
}

MOUNTIT_REGISTERED=/tmp/mountit_registered
MOUNTIT_LOCK=/tmp/mountit.lock
MOUNTIT_STOPPING=/tmp/mountit_stopping

# Run "$@" while holding Mount It's lock, so hot-plug, the lost-entry check and
# shutdown never change network storage at the same time
mountit::with_lock() {
    ( flock 9; "$@" ) 9> "$MOUNTIT_LOCK"
}

# Names of the network storage entries Mount It registered, one per line
mountit::registered.add() {
    grep -qxF "$1" "$MOUNTIT_REGISTERED" 2>/dev/null || echo "$1" >> "$MOUNTIT_REGISTERED"
}

mountit::registered.remove() {
    [[ -f "$MOUNTIT_REGISTERED" ]] || return 0
    grep -vxF "$1" "$MOUNTIT_REGISTERED" > "${MOUNTIT_REGISTERED}.tmp" || true
    mv "${MOUNTIT_REGISTERED}.tmp" "$MOUNTIT_REGISTERED"
}

# Close leftover "mount failed" repairs for <name>. At boot the Supervisor
# restores saved entries before Mount It's Samba server is up; they fail and it
# opens a repair offering Reload or Remove. Registering the entry again does not
# close that repair, and choosing Remove later deletes the working entry (#27).
mountit::mount.dismiss_failed_issue() {
    local name="$1" uuid
    while IFS= read -r uuid; do
        [[ -z "$uuid" ]] && continue
        bashio::api.supervisor DELETE "/resolution/issue/${uuid}" > /dev/null 2>&1 \
            && bashio::log.info "  $name — closed the leftover \"mount failed\" repair from boot"
    done < <(bashio::api.supervisor GET /resolution/info 2>/dev/null \
        | jq -r --arg n "$name" \
            '.issues[]? | select(.type == "mount_failed" and .reference == $n) | .uuid' 2>/dev/null \
        || true)
}

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
        if bashio::api.supervisor POST /mounts "$cmd" > /dev/null; then
            mountit::registered.add "$name"
            mountit::mount.dismiss_failed_issue "$name"
            return 0
        fi
        bashio::log.warning "  $name — attempt $rt/3 failed, retrying..."
        sleep 3
    done
    bashio::log.error "  $name — failed to register after 3 attempts"
    return 1
}

# Remove network storage entry <name>, but only if Mount It created it
mountit::mount.deregister() {
    local name="$1"
    mountit::registered.remove "$name"
    [[ "$(mountit::mount.owner "$name")" == "mountit" ]] || return 0
    bashio::api.supervisor DELETE "/mounts/${name}" > /dev/null 2>&1 \
        || bashio::log.warning "  $name — could not remove network storage entry"
}

# Register again every entry Mount It registered that has disappeared from the
# Supervisor while its drive is still mounted here (for example removed through
# a repair, #27), and send mountit_mount_lost for each. Run under the lock.
mountit::mount.check_lost() {
    local current name share usage reregistered names=()
    [[ -f "$MOUNTIT_STOPPING" ]] && return 0
    [[ -s "$MOUNTIT_REGISTERED" ]] || return 0
    # Supervisor busy or restarting: try again next time
    current=$(bashio::api.supervisor GET /mounts 2>/dev/null) || return 0
    mapfile -t names < "$MOUNTIT_REGISTERED"

    for name in "${names[@]}"; do
        [[ -z "$name" ]] && continue
        jq -e --arg n "$name" '.mounts[]? | select(.name == $n)' <<< "$current" > /dev/null 2>&1 && continue

        if jq -e --arg n "$name" '.[$n]' /tmp/mountit_mounts.json > /dev/null 2>&1; then
            share="$name"
            usage=$(bashio::config 'mount_location')
        elif jq -e --arg n "$name" '.[$n]' /tmp/mountit_folder_mounts.json > /dev/null 2>&1; then
            share=$(jq -r --arg n "$name" '.[$n].share' /tmp/mountit_folder_mounts.json)
            usage=$(jq -r --arg n "$name" '.[$n].location' /tmp/mountit_folder_mounts.json)
        else
            mountit::registered.remove "$name"
            continue
        fi

        bashio::log.warning "$name — network storage entry was removed outside Mount It, registering it again"
        reregistered=false
        if mountit::mount.register "$name" "$share" "$usage"; then
            reregistered=true
            bashio::log.green "  $name — registered again"
        fi
        mountit::event mount_lost "$(jq -nc --arg n "$name" --argjson r "$reregistered" \
            '{"name":$n,"reregistered":$r}')"
    done
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
