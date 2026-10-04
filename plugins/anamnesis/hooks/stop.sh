#!/usr/bin/env bash
# Claude Code Stop: after every assistant turn, upload the conversation
# added since the last upload (log_session) plus per-turn usage telemetry.
# All network work runs in a detached worker, so the hook returns at once.
# A per-transcript high-water mark records how many JSONL lines were sent;
# resending whole transcripts duplicated episodes on the server.

set -u
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=common.sh
. "$HOOK_DIR/common.sh"

anamnesis_load_config || exit 0

# Read stdin now: Claude Code closes the pipe when the hook exits.
STDIN_JSON="$(cat)"
anamnesis_resolve_sid "$STDIN_JSON"
if [ -z "$ANAMNESIS_SID" ]; then
    ANAMNESIS_SID="recovered-$(date -u +"%Y%m%dT%H%M%SZ")"
    anamnesis_write_session_id "$ANAMNESIS_SID"
fi
TRANSCRIPT_PATH="$(printf '%s' "$STDIN_JSON" | jq -r '.transcript_path // empty' 2>/dev/null)"
PENDING_RECEIPT="$ANAMNESIS_RECEIPT_DIR/pending_capture.$(anamnesis_transcript_key "$ANAMNESIS_SID").json"

# Foreground, no network: a rejected sign-in seen by an earlier worker, or
# the capture receipt (ADR-070) a worker deposited after a confirmed upload.
if anamnesis_auth_warning_due; then
    jq -n --arg msg "$ANAMNESIS_AUTH_WARNING" '{systemMessage: $msg}'
elif [ -f "$PENDING_RECEIPT" ]; then
    TURNS="$(jq -r '.turns // 0' < "$PENDING_RECEIPT" 2>/dev/null)"
    rm -f "$PENDING_RECEIPT"
    case "$TURNS" in ''|*[!0-9]*) TURNS=0 ;; esac
    if [ "$TURNS" -gt 0 ] && [ "$(anamnesis_receipts_level)" = "normal" ] \
        && anamnesis_receipt_once "capture"; then
        NOUN="turns"
        [ "$TURNS" -eq 1 ] && NOUN="turn"
        jq -n --arg msg "[anamnesis] session capture is live — $TURNS $NOUN backed up so far. /clear is free whenever you want it." \
            '{systemMessage: $msg}'
    fi
fi

anamnesis_stop_worker() {
    local filter body turns usage
    if [ -z "$TRANSCRIPT_PATH" ] || [ ! -r "$TRANSCRIPT_PATH" ]; then
        anamnesis_log_error "capture_skipped" "no readable transcript_path in the Stop payload"
        return 0
    fi
    anamnesis_delta_begin "$TRANSCRIPT_PATH" || return 0
    filter="$(anamnesis_capture_filter_mode)"

    # One row per line, parsed leniently: a malformed row loses only itself.
    # Text blocks only; thinking, tool_use and tool_result are dropped.
    turns="$(printf '%s\n' "$ANAMNESIS_DELTA" | jq -cR --arg filter "$filter" "$ANAMNESIS_JQ_CONVERSATION"'
        fromjson? | select(is_conversation) | conv_text | select(length > 0)' 2>/dev/null)"
    if [ -n "$turns" ]; then
        body="$(printf '%s\n' "$turns" | jq -sc --arg sid "$ANAMNESIS_SID" '{session_id: $sid, transcript: join("\n")}')"
        if anamnesis_post "/mcp/tools/log_session" "$body" >/dev/null; then
            if ! anamnesis_receipt_fired "capture"; then
                jq -n --arg sid "$ANAMNESIS_SID" --argjson t "$(printf '%s\n' "$turns" | wc -l | tr -d '[:space:]')" \
                    '{session_id: $sid, turns: $t}' > "$PENDING_RECEIPT" 2>/dev/null
            fi
        else
            anamnesis_queue_payload "/mcp/tools/log_session" "$body"
            anamnesis_log_error "log_session_queued" "sid=$ANAMNESIS_SID"
        fi
    fi

    # Usage telemetry, informational and fire-and-forget. Claude Code writes
    # one row per content block, each repeating its message's usage, so send
    # one record per message id.
    printf '%s\n' "$ANAMNESIS_DELTA" | jq -cR --arg sid "$ANAMNESIS_SID" -n '
        [inputs | fromjson? | select(.message?.usage?)
         | {input_tokens:                (.message.usage.input_tokens // 0),
            output_tokens:               (.message.usage.output_tokens // 0),
            cache_read_input_tokens:     (.message.usage.cache_read_input_tokens // 0),
            cache_creation_input_tokens: (.message.usage.cache_creation_input_tokens // 0),
            model:                       (.message.model // null),
            turn_id:                     (.message.id // .uuid // null),
            session_id: $sid, source: "claude_code_plugin"}]
        | (map(select(.turn_id == null)) + (map(select(.turn_id != null)) | unique_by(.turn_id)))
        | .[]' 2>/dev/null \
    | while IFS= read -r usage; do
        anamnesis_post "/mcp/tools/track_usage" "$usage" >/dev/null
    done

    anamnesis_delta_commit
}

# Detached with no fds on the hook's pipes, or Claude Code would wait for
# EOF; the worker outlives this script.
anamnesis_stop_worker </dev/null >/dev/null 2>&1 &
exit 0
