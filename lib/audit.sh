#!/usr/bin/env bash
# lib/audit.sh — Audit logging for dev-cli
# Sourced by bin/dev and bin/dev-admin

AUDIT_LOG="${AUDIT_LOG:-/etc/dev-cli/audit.log}"

# Write a JSON-lines audit entry
# Usage: audit_log <actor> <action> [target] [details_json]
audit_log() {
    local actor="$1" action="$2" target="${3:-}" details="${4:-{}}"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    [[ -z "$details" || "$details" == "" ]] && details='{}'
    local entry
    entry=$(jq -nc \
        --arg ts "$ts" \
        --arg actor "$actor" \
        --arg action "$action" \
        --arg target "$target" \
        --argjson details "$details" \
        '{ts: $ts, actor: $actor, action: $action, target: $target, details: $details}')
    echo "$entry" >> "$AUDIT_LOG"
}

# Read and filter audit log
# Usage: audit_read [--user <name>] [--action <type>] [--last <duration>]
audit_read() {
    local user="" action="" last=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --user) user="$2"; shift 2 ;;
            --action) action="$2"; shift 2 ;;
            --last) last="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local filter="."
    [[ -n "$user" ]] && filter="$filter | select(.actor == \"$user\")"
    [[ -n "$action" ]] && filter="$filter | select(.action | startswith(\"$action\"))"

    if [[ -n "$last" ]]; then
        local seconds=0
        case "$last" in
            *h) seconds=$(( ${last%h} * 3600 )) ;;
            *d) seconds=$(( ${last%d} * 86400 )) ;;
            *m) seconds=$(( ${last%m} * 60 )) ;;
            *) seconds="$last" ;;
        esac
        local cutoff
        cutoff=$(date -u -d "-${seconds} seconds" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                 date -u -v-${seconds}S +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
        if [[ -n "$cutoff" ]]; then
            filter="$filter | select(.ts >= \"$cutoff\")"
        fi
    fi

    [[ -f "$AUDIT_LOG" ]] || return 0
    jq -c "$filter" "$AUDIT_LOG"
}
