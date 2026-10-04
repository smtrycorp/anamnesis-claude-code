#!/usr/bin/env bash
# Claude Code SessionEnd: ask the server to advance this session's pipeline
# (episodes to echoes) now rather than in the nightly batch.

set -u
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=common.sh
. "$HOOK_DIR/common.sh"

anamnesis_load_config || exit 0

STDIN_JSON="$(cat)"
anamnesis_resolve_sid "$STDIN_JSON"
[ -n "$ANAMNESIS_SID" ] || exit 0
REASON="$(printf '%s' "$STDIN_JSON" | jq -r '.reason // "exit"' 2>/dev/null)"
[ -n "$REASON" ] || REASON="exit"

# Give a running Stop worker up to 15s to land the last turn, so reflection
# sees it; the nightly batch is the backstop if it does not.
TRANSCRIPT_PATH="$(printf '%s' "$STDIN_JSON" | jq -r '.transcript_path // empty' 2>/dev/null)"
if [ -n "$TRANSCRIPT_PATH" ]; then
    LOCK="$ANAMNESIS_STATE_DIR/$(anamnesis_transcript_key "$TRANSCRIPT_PATH").lck"
    anamnesis_lock_acquire "$LOCK" 30 && anamnesis_lock_release "$LOCK"
fi

BODY="$(jq -n --arg sid "$ANAMNESIS_SID" --arg reason "$REASON" '{session_id: $sid, reason: $reason}')"
if ! anamnesis_post "/mcp/tools/session_close" "$BODY" >/dev/null; then
    anamnesis_queue_payload "/mcp/tools/session_close" "$BODY"
    anamnesis_log_error "session_close_queued" "sid=$ANAMNESIS_SID reason=$REASON"
fi

# This session's receipt markers and any unshown capture receipt are spent.
SID_KEY="$(anamnesis_transcript_key "$ANAMNESIS_SID")"
rm -f "$ANAMNESIS_RECEIPT_DIR/$SID_KEY".* "$ANAMNESIS_RECEIPT_DIR/pending_capture.$SID_KEY.json"
anamnesis_receipt_prune
anamnesis_clear_session_id "$ANAMNESIS_SID"
exit 0
