#!/bin/bash
# Capture filter (ADMISSION-1): conversation records in, control records out, by structural fields only.
set -u
cd "$(dirname "$0")/.."
. plugins/anamnesis/hooks/capture-filter.sh
run() { jq -r --arg filter "$1" "$ANAMNESIS_JQ_CONVERSATION"' select(is_conversation) | conv_text | select(length > 0)'; }
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi; }
FIX='
{"type":"user","message":{"role":"user","content":"Please make the header solid."},"origin":{"kind":"human"}}
{"type":"user","message":{"role":"user","content":"Legacy user turn with no origin field."}}
{"type":"user","message":{"role":"user","content":"I typed <task-notification> on purpose to ask what it means."},"origin":{"kind":"human"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done: header is solid."},{"type":"tool_use","name":"Bash"}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"stdout blah"}]}}
{"type":"queue-operation","operation":"enqueue","content":"<task-notification><task-id>b1</task-id><status>completed</status></task-notification>"}
{"type":"user","message":{"role":"user","content":"<task-notification><task-id>b2</task-id></task-notification>"},"origin":{"kind":"task-notification"}}
{"type":"user","isMeta":true,"message":{"role":"user","content":[{"type":"text","text":"[Image: source: /tmp/x.png]"}]}}
{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"This session is being continued from a previous conversation..."}}
{"type":"user","message":{"role":"user","content":"<command-name>/model</command-name> <command-message>model</command-message>"}}
{"type":"user","message":{"role":"user","content":"<local-command-stdout>Set model to Opus</local-command-stdout>"}}
{"type":"user","isMeta":true,"message":{"role":"user","content":"Continue from where you left off."},"origin":{"kind":"auto-continuation"}}
{"type":"user","message":{"role":"user","content":"<command-name> is the tag I want to ask about: why does it appear?"},"origin":{"kind":"human"}}
{"type":"attachment","attachment":{"type":"queued_command","commandMode":"prompt","prompt":"Also, glimmer should be the default for Tyche.","origin":{"kind":"human"}}}
{"type":"attachment","attachment":{"type":"queued_command","commandMode":"prompt","prompt":"[Subagent hand-back] review written","origin":{"kind":"peer","from":"a1"}}}
{"type":"attachment","attachment":{"type":"queued_command","commandMode":"task-notification","prompt":"<task-notification><task-id>b3</task-id></task-notification>"}}
{"type":"assistant","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You have hit your session limit"}]}}
{"type":"user","message":{"role":"user","content":"<task-notification><task-id>b4</task-id><status>completed</status></task-notification>"}}
{"type":"system","content":"Conversation compacted"}
{"type":"attachment","attachment":{"type":"hook_additional_context","content":"<anamnesis-context>recalled</anamnesis-context>"}}
{"type":"ai-title","content":"Some title"}
'
ON="$(printf '%s' "$FIX" | sed '/^$/d' | run on)"
OFF="$(printf '%s' "$FIX" | sed '/^$/d' | run off)"
check "human turn kept"            "$(grep -c 'Please make the header solid' <<<"$ON")" 1
check "legacy no-origin turn kept" "$(grep -c 'Legacy user turn' <<<"$ON")" 1
check "human mention of tag kept"  "$(grep -c 'I typed <task-notification>' <<<"$ON")" 1
check "assistant text kept"        "$(grep -c 'Done: header is solid' <<<"$ON")" 1
check "tool_use/result dropped"    "$(grep -c 'stdout blah' <<<"$ON")" 0
check "queue-operation dropped"    "$(grep -c '<task-id>b1' <<<"$ON")" 0
check "task-notification dropped"  "$(grep -c '<task-id>b2' <<<"$ON")" 0
check "isMeta image stub dropped"  "$(grep -c 'Image: source' <<<"$ON")" 0
check "compact summary dropped"    "$(grep -c 'being continued' <<<"$ON")" 0
check "slash command dropped"      "$(grep -c '/model</command-name>' <<<"$ON")" 0
check "local-command dropped"      "$(grep -c 'Set model to Opus' <<<"$ON")" 0
check "auto-continuation dropped"  "$(grep -c 'Continue from where' <<<"$ON")" 0
check "human starting with a tag kept" "$(grep -c 'is the tag I want to ask about' <<<"$ON")" 1
check "queued human prompt kept"   "$(grep -c 'glimmer should be the default' <<<"$ON")" 1
check "queued peer hand-back dropped" "$(grep -c 'Subagent hand-back' <<<"$ON")" 0
check "queued task-notif dropped"  "$(grep -c '<task-id>b3' <<<"$ON")" 0
check "api error record dropped"   "$(grep -c 'hit your session limit' <<<"$ON")" 0
check "old-CC bare notif dropped"  "$(grep -c '<task-id>b4' <<<"$ON")" 0
check "off: queued prompt not added" "$(grep -c 'glimmer should be the default' <<<"$OFF")" 0
LEGACY="$(printf '%s' "$FIX" | sed '/^$/d' | jq -r '(.message.content // .content // .text // "") as $c | if ($c|type)=="array" then [ $c[] | select(.type=="text") | (.text // empty) ] | join("\n") elif ($c|type)=="string" then $c else "" end' | sed '/^$/d')"
check "off: identical to the original extractor" "$([ "$(sed '/^$/d' <<<"$OFF")" = "$LEGACY" ] && echo same)" same
check "system dropped"             "$(grep -c 'Conversation compacted' <<<"$ON")" 0
check "ai-title dropped"           "$(grep -c 'Some title' <<<"$ON")" 0
check "filter=off keeps old path"  "$(grep -c '<task-id>b1' <<<"$OFF")" 1
exit $fail
