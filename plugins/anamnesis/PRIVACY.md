# Privacy — anamnesis Claude Code plugin

## What the hooks send, and when

The hooks run on your machine and send to the `server_url` in
`~/.anamnesis/config.json` (by default `https://anamnesis.smtry.ai`) over
HTTPS:

- **SessionStart.** In the background: any payloads queued after an earlier
  failed upload (conversation text or a session close), then a
  `get_memory_stats` reachability probe. On a resume or compaction (not on a
  fresh start or `/clear`) it also fetches this session's server-side cache
  by session id and adds it to the model's context as reference material.
- **UserPromptSubmit.** Your prompt text and the session id, as a
  `retrieve_memories` query. Up to five recalled lines and a date/time
  anchor are added to the turn's context.
- **Stop.** In the background, after each assistant turn: the conversation
  text added since the last upload (prompts you typed and Claude's text
  replies; not tool calls, tool output or thinking), with the session id,
  to `log_session`. Also usage telemetry for each new assistant message:
  input, output and cache token counts, the model name, the message id and
  the session id, to `track_usage`.
- **SessionEnd.** The session id and the close reason, to `session_close`.

Every request carries `Authorization: Bearer <access token>` (OAuth), or
`X-Anamnesis-Key: <api_key>` for a legacy api_key install. When the access
token is near expiry, the refresh token and client id go to `/oauth/token`.
Credentials and bodies reach `curl` through 0600 files or stdin, never its
command line.

## When nothing is sent

With `anamnesis pause` in effect, or `ANAMNESIS_CAPTURE` set to `off`, `0`,
`false` or `no` (any case; an unrecognised value also counts as off), every
hook exits without sending anything or adding anything to context, and the
upload queue is not replayed.

The plugin also registers Anamnesis as a remote MCP server that Claude Code
connects to itself. Tools the model calls through it (for example
`remember_episode`) are not covered by the pause file or `ANAMNESIS_CAPTURE`.

## What stays on your machine

`~/.anamnesis/` holds your tokens (`config.json`), payloads waiting to be
uploaded (`pending_uploads/`, plaintext conversation text until delivered),
per-transcript upload progress, receipt markers and an error log. Files the
hooks create are mode 0600.

## What the server does

Content is encrypted at rest under a per-user key derived from your own
api_key, with no master key. It is not yet end-to-end encrypted:
[anamnesis.smtry.ai/security](https://anamnesis.smtry.ai/security) says
exactly who can decrypt what, and
[anamnesis.smtry.ai/privacy](https://anamnesis.smtry.ai/privacy) has the full
policy, including subprocessors and retention.

## Pausing / revoking

- `anamnesis pause` stops the hooks until `anamnesis resume`.
- `anamnesis-config` signs in again and replaces the stored tokens.
- Delete individual memories or wipe everything at
  [anamnesis.smtry.ai/memory](https://anamnesis.smtry.ai/memory).

## Uninstall

```
/plugin uninstall anamnesis@smtry
rm -rf ~/.anamnesis
```

Server-side deletion is a separate action at `/memory`.
