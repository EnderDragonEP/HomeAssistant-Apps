#!/usr/bin/env bash
# Regression checks for the runtime libraries. Run this checkout bind-mounted
# into the built addon image, which provides jq and the same Alpine userland.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
case "$test_root" in
    /tmp/*) ;;
    *) printf 'Refusing unsafe test cleanup path: %s\n' "$test_root" >&2; exit 1 ;;
esac
trap 'rm -rf "$test_root"' EXIT

failures=0

fail() {
    printf 'not ok - %s\n' "$1" >&2
    ((failures += 1))
}

pass() {
    printf 'ok - %s\n' "$1"
}

assert_eq() {
    local expected="$1" actual="$2" description="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$description"
    else
        fail "$description (expected '$expected', got '$actual')"
    fi
}

assert_true() {
    local description="$1"
    shift
    if "$@"; then
        pass "$description"
    else
        fail "$description"
    fi
}

bashio::log.info() { :; }
bashio::log.warning() { :; }
bashio::log.error() { :; }
bashio::log.green() { :; }
bashio::config() {
    [[ "$1" == "mount_location" ]] && printf 'media\n'
}

# ---- Persistent credential regression ----
export MOUNTIT_DATA_DIR="$test_root/data"
export MOUNTIT_RUNTIME_DIR="$test_root/runtime"
mkdir -p "$MOUNTIT_DATA_DIR" "$MOUNTIT_RUNTIME_DIR"

credentials_lib="$repo_root/rootfs/usr/local/lib/mountit-credentials.sh"
supervisor_lib="$repo_root/rootfs/usr/local/lib/mountit-supervisor.sh"
[[ -f "$credentials_lib" ]] || credentials_lib=/usr/local/lib/mountit-credentials.sh
[[ -f "$supervisor_lib" ]] || supervisor_lib=/usr/local/lib/mountit-supervisor.sh

# shellcheck source=../rootfs/usr/local/lib/mountit-credentials.sh
source "$credentials_lib"

if mountit::prepare_credentials; then
    first_password=$(cat "$MOUNTIT_PASSWORD_FILE")
    if [[ "$first_password" =~ ^[A-Fa-f0-9]{20}$ ]]; then
        pass "first start creates a 20-character hexadecimal credential"
    else
        fail "first start creates a 20-character hexadecimal credential"
    fi
    assert_eq "600" "$(stat -c '%a' "$MOUNTIT_PASSWORD_FILE")" \
        "persistent credential permissions are 0600"
    assert_eq "600" "$(stat -c '%a' "$MOUNTIT_RUNTIME_PASSWORD_FILE")" \
        "runtime credential permissions are 0600"
    assert_eq "600" "$(stat -c '%a' "$MOUNTIT_SMB_AUTH_FILE")" \
        "Samba preflight authentication file permissions are 0600"
else
    fail "first start prepares credentials"
    first_password=""
fi

rm -f "$MOUNTIT_RUNTIME_PASSWORD_FILE" "$MOUNTIT_SMB_AUTH_FILE"
mountit::generate_password() { printf 'ffffffffffffffffffff'; }
if mountit::prepare_credentials; then
    assert_eq "$first_password" "$(cat "$MOUNTIT_PASSWORD_FILE")" \
        "restart reuses the persistent credential"
    assert_eq "$first_password" "$(cat "$MOUNTIT_RUNTIME_PASSWORD_FILE")" \
        "runtime credential matches the persistent credential"
else
    fail "restart prepares credentials"
fi

printf 'broken\n' > "$MOUNTIT_PASSWORD_FILE"
mountit::generate_password() { printf cccccccccccccccccccc; }
if mountit::prepare_credentials; then
    assert_eq "cccccccccccccccccccc" "$(cat "$MOUNTIT_PASSWORD_FILE")" \
        "a corrupted app-owned credential is regenerated atomically"
else
    fail "corrupted credential is repaired"
fi

# ---- Supervisor reconciliation regression ----
printf '172.30.32.1\n' > "$MOUNTIT_RUNTIME_DIR/mountit_ip"
printf '{}\n' > "$MOUNTIT_RUNTIME_DIR/mountit_mounts.json"
printf '{}\n' > "$MOUNTIT_RUNTIME_DIR/mountit_folder_mounts.json"
export SUPERVISOR_TOKEN='test-token'
export MOUNTIT_RETRY_DELAYS='0 0'
export MOUNTIT_VERIFY_DELAYS='0'
export MOUNTIT_REMOVE_DELAYS='0 0'

# shellcheck source=../rootfs/usr/local/lib/mountit-supervisor.sh
source "$supervisor_lib"
mountit::init_supervisor_context || fail "Supervisor test context initializes"

runtime_password=$(cat "$MOUNTIT_RUNTIME_PASSWORD_FILE")
printf 'dddddddddddddddddddd\n' > "$MOUNTIT_PASSWORD_FILE"
mountit::init_supervisor_context || fail "Supervisor context tolerates a concurrently changed data file"
expected_runtime_id=$(printf '%s' "$runtime_password" | sha256sum | awk '{print $1}')
assert_eq "$expected_runtime_id" "$MOUNTIT_CREDENTIAL_ID" \
    "credential generation identifies the exact password sent to Supervisor"
printf '%s\n' "$runtime_password" > "$MOUNTIT_PASSWORD_FILE"

MOCK_ENTRY=''
MOCK_CREATE_FAILURES=0
MOCK_PUT_FAILURES=0
MOCK_PUT_COMMIT_THEN_FAILS=0
MOCK_GET_FAILURES=0
MOCK_GET_FAILURES_AFTER_PUT=0
MOCK_DELETE_AMBIGUOUS_KEEP_ENTRY=0
MOCK_RELOAD_FAILURES=0
MOCK_LAST_MUTATION_BODY=''
MOCK_CALLS=()

mountit::probe_share() { return 0; }

mountit::api() {
    local method="$1" resource="$2" body="${3:-}"
    local name
    MOCK_CALLS+=("$method $resource")
    MOUNTIT_API_ERROR='mock failure'
    MOUNTIT_API_DATA='{}'
    MOUNTIT_API_AMBIGUOUS=false
    [[ -z "$body" ]] || MOCK_LAST_MUTATION_BODY="$body"

    if [[ "$method $resource" == "GET /mounts" ]]; then
        if ((MOCK_GET_FAILURES > 0)); then
            MOCK_GET_FAILURES=$((MOCK_GET_FAILURES - 1))
            return 1
        fi
        if [[ -n "$MOCK_ENTRY" ]]; then
            MOUNTIT_API_DATA=$(jq -nc --argjson entry "$MOCK_ENTRY" '{mounts:[$entry]}')
        else
            MOUNTIT_API_DATA='{"mounts":[]}'
        fi
        MOUNTIT_API_ERROR=''
        return 0
    fi

    if [[ "$method $resource" == "POST /mounts" ]]; then
        if ((MOCK_CREATE_FAILURES > 0)); then
            MOCK_CREATE_FAILURES=$((MOCK_CREATE_FAILURES - 1))
            return 1
        fi
        MOCK_ENTRY=$(jq -c '. + {state:"active",read_only:false}' <<< "$body")
        MOUNTIT_API_ERROR=''
        return 0
    fi

    if [[ "$method" == "PUT" ]]; then
        name="${resource##*/}"
        if ((MOCK_PUT_COMMIT_THEN_FAILS > 0)); then
            MOCK_PUT_COMMIT_THEN_FAILS=$((MOCK_PUT_COMMIT_THEN_FAILS - 1))
            MOCK_ENTRY=$(jq -c --arg name "$name" '. + {name:$name,state:"active",read_only:false}' <<< "$body")
            MOUNTIT_API_AMBIGUOUS=true
            return 1
        fi
        if ((MOCK_PUT_FAILURES > 0)); then
            MOCK_PUT_FAILURES=$((MOCK_PUT_FAILURES - 1))
            return 1
        fi
        MOCK_ENTRY=$(jq -c --arg name "$name" '. + {name:$name,state:"active",read_only:false}' <<< "$body")
        if ((MOCK_GET_FAILURES_AFTER_PUT > 0)); then
            MOCK_GET_FAILURES=$MOCK_GET_FAILURES_AFTER_PUT
            MOCK_GET_FAILURES_AFTER_PUT=0
        fi
        MOUNTIT_API_ERROR=''
        return 0
    fi

    if [[ "$method" == "POST" && "$resource" == */reload ]]; then
        if ((MOCK_RELOAD_FAILURES > 0)); then
            MOCK_RELOAD_FAILURES=$((MOCK_RELOAD_FAILURES - 1))
            # Model a stale/cached Supervisor read that still reports active
            # after reload failed to recreate its credential file.
            MOCK_ENTRY=$(jq -c '.state = "active"' <<< "$MOCK_ENTRY")
            return 1
        fi
        MOCK_ENTRY=$(jq -c '.state = "active"' <<< "$MOCK_ENTRY")
        MOUNTIT_API_ERROR=''
        return 0
    fi

    if [[ "$method" == "DELETE" ]]; then
        if ((MOCK_DELETE_AMBIGUOUS_KEEP_ENTRY > 0)); then
            MOCK_DELETE_AMBIGUOUS_KEEP_ENTRY=$((MOCK_DELETE_AMBIGUOUS_KEEP_ENTRY - 1))
            MOUNTIT_API_AMBIGUOUS=true
            return 1
        fi
        MOCK_ENTRY=''
        MOUNTIT_API_ERROR=''
        return 0
    fi

    return 1
}

count_call() {
    local wanted="$1" count=0 call
    for call in "${MOCK_CALLS[@]}"; do
        [[ "$call" == "$wanted" ]] && ((count += 1))
    done
    printf '%s\n' "$count"
}

use_test_password() {
    MOUNTIT_PASSWORD="$1"
    MOUNTIT_CREDENTIAL_ID=$(printf '%s' "$MOUNTIT_PASSWORD" | sha256sum | awk '{print $1}')
}

if mountit::reconcile_mount BigNoodle BigNoodle media drive BigNoodle true; then
    assert_eq "1" "$(count_call 'POST /mounts')" "absent storage is created once"
    assert_eq "0" "$(count_call 'DELETE /mounts/BigNoodle')" "creation never performs a blind delete"
else
    fail "absent storage reconciles"
fi

MOCK_CALLS=()
use_test_password 11111111111111111111
MOCK_PUT_COMMIT_THEN_FAILS=1
if mountit::reconcile_mount BigNoodle BigNoodle media drive BigNoodle true; then
    ambiguous_update_status=0
else
    ambiguous_update_status=$?
fi
assert_eq "1" "$ambiguous_update_status" "an ambiguous update is deferred"
assert_eq "1" "$(count_call 'PUT /mounts/BigNoodle')" \
    "an ambiguous update is never repeated in the same pass"
assert_eq "0" "$(count_call 'POST /mounts/BigNoodle/reload')" \
    "reload is not treated as proof that an ambiguous password update succeeded"
assert_true "an ambiguous update does not mark the credential synchronized" \
    jq -e --arg id "$MOUNTIT_CREDENTIAL_ID" '.BigNoodle.credential_id != $id' "$MOUNTIT_MANAGED_FILE"
if mountit::reconcile_mount BigNoodle BigNoodle media drive BigNoodle true; then
    second_ambiguous_update_status=0
else
    second_ambiguous_update_status=$?
fi
assert_eq "1" "$second_ambiguous_update_status" \
    "a later pass defers an ambiguous update during the operation holdoff"
assert_eq "1" "$(count_call 'PUT /mounts/BigNoodle')" \
    "an ambiguous update is not repeated by the next reconciliation pass"

MOCK_CALLS=()
MOUNTIT_OPERATION_HOLDOFF=0
use_test_password 22222222222222222222
MOCK_GET_FAILURES_AFTER_PUT=1
if mountit::reconcile_mount BigNoodle BigNoodle media drive BigNoodle true; then
    assert_eq "1" "$(count_call 'PUT /mounts/BigNoodle')" \
        "a successful update is not repeated after a failed verification read"
    assert_eq "$MOUNTIT_PASSWORD" "$(jq -r '.password' <<< "$MOCK_LAST_MUTATION_BODY")" \
        "credential refresh sends the new persistent password"
else
    fail "a definitively accepted update survives a failed verification read"
fi
MOUNTIT_OPERATION_HOLDOFF=300

MOCK_CALLS=()
if mountit::reconcile_mount BigNoodle BigNoodle media drive BigNoodle true; then
    assert_eq "0" "$(count_call 'POST /mounts')" "matching active storage is left untouched"
    assert_eq "0" "$(count_call 'PUT /mounts/BigNoodle')" "synced credentials avoid repeated updates"
else
    fail "matching active storage reconciles"
fi

MOCK_CALLS=()
MOCK_ENTRY=$(jq -c '.state = "failed"' <<< "$MOCK_ENTRY")
if mountit::reconcile_mount BigNoodle BigNoodle media drive BigNoodle true; then
    assert_eq "1" "$(count_call 'POST /mounts/BigNoodle/reload')" "failed owned storage is reloaded"
else
    fail "failed owned storage reloads"
fi

MOCK_CALLS=()
MOCK_ENTRY=$(jq -c '.state = "failed"' <<< "$MOCK_ENTRY")
MOCK_RELOAD_FAILURES=1
if mountit::reconcile_mount BigNoodle BigNoodle media drive BigNoodle true; then
    assert_eq "1" "$(count_call 'POST /mounts/BigNoodle/reload')" \
        "a failed reload is attempted once"
    assert_eq "1" "$(count_call 'PUT /mounts/BigNoodle')" \
        "a failed reload refreshes credentials through PUT despite a stale active state"
else
    fail "failed reload falls back to a credential refresh"
fi

MOCK_CALLS=()
use_test_password 33333333333333333333
if mountit::reconcile_mount BigNoodle BigNoodle media drive BigNoodle true; then
    assert_eq "1" "$(count_call 'PUT /mounts/BigNoodle')" \
        "a new persistent credential refreshes an existing active entry once"
else
    fail "credential migration refreshes storage"
fi

MOCK_CALLS=()
use_test_password 44444444444444444444
MOCK_PUT_FAILURES=1
if mountit::reconcile_mount BigNoodle BigNoodle media drive BigNoodle true; then
    assert_eq "2" "$(count_call 'PUT /mounts/BigNoodle')" \
        "failed credential refresh is retried instead of accepting the old active unit"
    assert_true "credential generation is recorded only after PUT succeeds" \
        jq -e --arg id "$MOUNTIT_CREDENTIAL_ID" '.BigNoodle.credential_id == $id' "$MOUNTIT_MANAGED_FILE"
else
    fail "failed credential refresh eventually recovers"
fi

MOCK_CALLS=()
MOCK_ENTRY=''
MOCK_CREATE_FAILURES=1
if mountit::reconcile_mount Orphaned Orphaned media drive Orphaned true; then
    assert_eq "2" "$(count_call 'POST /mounts')" \
        "orphan-unit create failure is retried after Supervisor cleanup"
else
    fail "orphan-unit failure recovers"
fi

MOCK_CALLS=()
mountit::write_state_entry "$MOUNTIT_MANAGED_FILE" Moving OldShare media drive Moving
MOCK_ENTRY='{"name":"Moving","type":"cifs","server":"172.30.32.1","share":"OldShare","usage":"media","state":"reloading"}'
if mountit::reconcile_mount Moving NewShare media drive Moving true; then
    moving_status=0
else
    moving_status=$?
fi
assert_eq "1" "$moving_status" "a transitional manifest-owned mount is deferred"
assert_eq "0" "$(count_call 'PUT /mounts/Moving')" \
    "a transitional manifest-owned mount is never updated concurrently"

MOCK_CALLS=()
MOCK_ENTRY='{"name":"Removing","type":"cifs","server":"172.30.32.1","share":"Removing","usage":"media","state":"active"}'
MOCK_DELETE_AMBIGUOUS_KEEP_ENTRY=1
if mountit::remove_mount Removing 172.30.32.1 Removing true; then
    ambiguous_delete_status=0
else
    ambiguous_delete_status=$?
fi
assert_eq "1" "$ambiguous_delete_status" "an ambiguous removal is deferred"
assert_eq "1" "$(count_call 'DELETE /mounts/Removing')" \
    "an ambiguous removal never submits a second DELETE"
if mountit::remove_mount Removing 172.30.32.1 Removing true; then
    second_ambiguous_delete_status=0
else
    second_ambiguous_delete_status=$?
fi
assert_eq "1" "$second_ambiguous_delete_status" \
    "a later cleanup pass defers an ambiguous removal during the operation holdoff"
assert_eq "1" "$(count_call 'DELETE /mounts/Removing')" \
    "an ambiguous removal is not repeated by the next cleanup pass"

MOCK_CALLS=()
MOCK_ENTRY='{"name":"CleanRemoval","type":"cifs","server":"172.30.32.1","share":"CleanRemoval","usage":"media","state":"active"}'
mountit::record_pending CleanRemoval CleanRemoval media drive CleanRemoval "$MOCK_ENTRY"
if mountit::remove_mount CleanRemoval 172.30.32.1 CleanRemoval true; then
    assert_true "verified removal clears accepted-pending metadata" \
        jq -e '.CleanRemoval.pending != true and (.CleanRemoval.operation // "") == ""' "$MOUNTIT_MANAGED_FILE"
else
    fail "verified removal succeeds"
fi
MOCK_CALLS=()
if mountit::reconcile_mount CleanRemoval CleanRemoval media drive CleanRemoval true; then
    assert_eq "1" "$(count_call 'POST /mounts')" \
        "a deliberately removed mount is recreated immediately on the next start"
else
    fail "a deliberately removed mount can be recreated immediately"
fi

MOCK_CALLS=()
mountit::forget_managed Unclassified || true
MOCK_ENTRY='{"name":"Unclassified","type":"cifs","server":"172.30.32.1","share":"Unclassified","usage":"media","state":"active"}'
MOCK_DELETE_AMBIGUOUS_KEEP_ENTRY=1
if mountit::remove_mount Unclassified 172.30.32.1 Unclassified true; then
    unclassified_remove_status=0
else
    unclassified_remove_status=$?
fi
assert_eq "1" "$unclassified_remove_status" \
    "an interrupted first cleanup is retained for later pruning"
MOUNTIT_OPERATION_HOLDOFF=0
if mountit::prune_managed_mounts true; then
    assert_true "unclassified interrupted cleanup is pruned after its holdoff" \
        jq -e 'has("Unclassified") | not' "$MOUNTIT_MANAGED_FILE"
else
    fail "unclassified interrupted cleanup is retried by pruning"
fi
MOUNTIT_OPERATION_HOLDOFF=300

MOCK_CALLS=()
MOCK_ENTRY='{"name":"Foreign","type":"cifs","server":"172.30.32.1","share":"Other","usage":"media","state":"active"}'
if mountit::reconcile_mount Foreign Foreign media drive Foreign true; then
    foreign_status=0
else
    foreign_status=$?
fi
assert_eq "2" "$foreign_status" "foreign same-name storage is reported as a collision"
assert_eq "0" "$(count_call 'POST /mounts')" "foreign storage is never overwritten"
assert_eq "0" "$(count_call 'DELETE /mounts/Foreign')" "foreign storage is never deleted"

if ((failures > 0)); then
    printf '%s lifecycle test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'All mount lifecycle tests passed\n'
