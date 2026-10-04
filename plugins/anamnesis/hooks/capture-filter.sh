#!/usr/bin/env bash
# Which Claude Code transcript records are conversation, decided by the
# record's own structural fields, never by matching words in the text.
# Sourced by stop.sh and by tests/test_capture_filter.sh.
# Kept: assistant turns, user turns a human typed, and prompts the human
# queued while Claude worked (a queued_command attachment with origin human).
# Dropped: queue operations, user records whose origin is not human,
# isMeta records, compaction summaries (they restate the whole session),
# system and bookkeeping records, slash-command envelopes (a user record that
# both opens and closes as a <command-*> or <local-command-*> wrapper),
# synthetic API-error assistant records, and on Claude Code versions without
# origin fields, a user record that is entirely a <task-notification>.
# ANAMNESIS_CAPTURE_FILTER=off keeps every record's text.
# shellcheck disable=SC2016,SC2034  # a jq program read by stop.sh; $filter is jq's, not the shell's
ANAMNESIS_JQ_CONVERSATION='
  def conv_text:
    if $filter == "on" and .type == "attachment" then (.attachment.prompt // "" | if type == "string" then . else "" end)
    else
      (.message.content // .content // .text // "") as $c
      | if   ($c | type) == "array"  then [ $c[] | select(.type == "text") | (.text // empty) ] | join("\n")
        elif ($c | type) == "string" then $c
        else "" end
    end;
  def conv_role: if .type == "assistant" then "assistant" else "user" end;
  def envelope($open; $close):
    test("^\\s*<(" + $open + ")>") and test("</(" + $close + ")>\\s*$");
  def is_conversation:
    if $filter != "on" then true
    elif .type == "assistant" then ((.isApiErrorMessage // false) | not)
    elif .type == "user" then
      ((.isMeta // false) | not)
      and ((.isCompactSummary // false) | not)
      and ((.origin == null) or (.origin.kind == "human"))
      and ((conv_text | envelope("command-name|command-message|local-command-[a-z]+"; "command-[a-z]+|local-command-[a-z]+")) | not)
      and ((.origin != null) or ((conv_text | envelope("task-notification"; "task-notification")) | not))
    elif .type == "attachment" then
      .attachment.type == "queued_command"
      and .attachment.commandMode == "prompt"
      and (.attachment.origin.kind == "human")
    else false end;
'
anamnesis_capture_filter_mode() {
    case "${ANAMNESIS_CAPTURE_FILTER:-on}" in off|OFF|0|false) echo off ;; *) echo on ;; esac
}
