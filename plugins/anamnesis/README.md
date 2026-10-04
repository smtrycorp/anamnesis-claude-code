# anamnesis — persistent encrypted memory for Claude Code

Four lifecycle hooks capture every session. Content is encrypted at rest
under a per-user key with no master key; not yet end-to-end, and
[anamnesis.smtry.ai/security](https://anamnesis.smtry.ai/security) says
exactly who can decrypt what. Browse, search, and delete any memory at
[anamnesis.smtry.ai/memory](https://anamnesis.smtry.ai/memory). What is
sent, and when, is in [PRIVACY.md](PRIVACY.md).

## Install

```
/plugin marketplace add https://github.com/israelashley/anamnesis-claude-code
/plugin install anamnesis@smtry
```

Then, once:

```
anamnesis-config                  # interactive — opens browser for OAuth consent
```

`anamnesis-config` starts a loopback server, registers a Dynamic Client
(RFC 7591), opens your browser to `anamnesis.smtry.ai/oauth/authorize`,
and catches the redirect. You paste your api_key on the consent page,
approve the scopes (`memory.read memory.write` by default — add
`--allow-delete` to also request `memory.delete`), and return to the
terminal. The access + refresh tokens land in `~/.anamnesis/config.json`
(mode 0600); hooks rotate the refresh token automatically before
expiry, so the setup is one-and-done.

Scripted installs (CI, headless servers) can skip the browser with
`anamnesis-config --api-key - --handle jia < keyfile`, which stores the
api_key itself and sends it as the `X-Anamnesis-Key` header. Prefer OAuth
where a browser is available.

## What the hooks do

| Hook | When | What it does |
|------|------|--------------|
| `SessionStart` | Once per session | Adopts Claude Code's `session_id`. In the background, replays the pending-upload queue and probes the server. On resume or compaction, injects this session's server-side cache as reference context. |
| `UserPromptSubmit` | Before every user turn | Retrieves up to 5 relevant memories and injects them with a `<current-datetime>` anchor (local clock, plus server UTC from the HTTP `Date:` header) as `additionalContext`. Gives up after about 3 seconds so a slow server never holds the prompt. |
| `Stop` | After every assistant turn | In the background, uploads the conversation added since the last upload via `log_session`, plus per-message usage telemetry (token counts, model) via `track_usage`. |
| `SessionEnd` | Session close | Calls `session_close`, advancing the server-side pipeline (episodes → echoes). |

Each hook takes the session id from its own Claude Code payload, so
parallel sessions never share one. All four are bash scripts that use
`curl` + `jq`. No Node, no
compiled binaries. `python3` is only required once, by `anamnesis-config`,
for the PKCE loopback server during the OAuth consent flow — hooks
themselves stay shell-only.

## Control surface

```
anamnesis                  status (default)
anamnesis pause            suspend capture — hooks become no-ops
anamnesis resume           re-enable capture
```

While `~/.anamnesis/paused` exists, every hook exits without sending
anything. `ANAMNESIS_CAPTURE=off` (or `0`, `false`, `no`, any case) does the
same for one process tree, which is how eval and review harnesses keep their
sessions out of your memory. Neither switch covers the remote MCP server
Claude Code connects to itself; see [PRIVACY.md](PRIVACY.md).

## Receipts — proof it's working, at zero token cost

Occasionally the plugin prints a tagged status line in your terminal:

```
[anamnesis] recalled 4 memories for this prompt — context you didn't have to re-explain
[anamnesis] session capture is live — 12 turns backed up so far. /clear is free whenever you want it.
```

Receipts are **state-triggered, never scheduled** — one fires because
something measurable just happened (a recall served, a capture landed),
at most once per session per kind. They are delivered through the hook
`systemMessage` channel, which renders to *you* but is never added to
the model's context: a receipt costs **0 tokens**, and CI asserts that
receipt text can never appear in injected context.

Why they exist: memory infrastructure is invisible precisely when it's
working. Receipts are the visible heartbeat — and the capture receipt
carries the practical tip that matters most: once your session is backed
up, `/clear` is free. A fresh context window is cheaper *and* sharper,
and Anamnesis is what makes clearing survivable.

Tune them with the `receipts` key in `~/.anamnesis/config.json`:

| Value | Effect |
|-------|--------|
| `"normal"` (default) | All receipt kinds. |
| `"minimal"` | Reserved for high-value receipts only (context-pressure and compaction notices, coming in 0.4.x) — current informational receipts are silenced. |
| `"off"` | No receipts, ever. Capture and recall behave identically — visibility is a default, never a hostage. |

## What makes this different from claude-mem and mem0

The hook shape is borrowed — Stop-per-turn, fail-open, per-event JSON
input — because those patterns are correct. What's ours:

1. **Crypto posture.** Per-user HKDF-derived keys — no master key, so a
   bulk database compromise alone decrypts nothing. Not yet end-to-end:
   client-held keys are the roadmap, and
   [anamnesis.smtry.ai/security](https://anamnesis.smtry.ai/security)
   says exactly who can decrypt what. Memory tools typically ship
   plaintext on disk or manage keys entirely server-side; we publish the
   boundary and the roadmap past it.
2. **Pipeline structure.** Episodes → Echoes → Engrams with explicit
   quality gates and reject-and-audit. Low-signal content is quarantined
   with a reason, not silently curated.
3. **Visible memory.** Browse, search, and delete your memory as a
   first-class UI at `/memory`. Competitors ship text files on disk or
   developer APIs.
4. **Time grounding.** Every `UserPromptSubmit` injection carries a
   `<current-datetime>` line with the local clock (day of week, time zone)
   and, when the server answered, its UTC time from the HTTP `Date`
   header. It goes out even when retrieval fails.
5. **Cross-client fidelity.** The same MCP server backs this plugin,
   Claude Desktop, and any MCP-aware client. Install the plugin on
   Claude Code and the connector on Claude Desktop: same api_key, same
   memory root, same encryption.
6. **Control surface.** `anamnesis pause|resume|status` as first-class
   commands — not a config file you have to remember the shape of.

## Configuration files

| Path | Contents | Mode |
|------|----------|------|
| `~/.anamnesis/config.json` | OAuth: handle, server_url, access_token, refresh_token, expires_at, client_id. Legacy: api_key, handle, server_url. | 0600 |
| `~/.anamnesis/current_session.json` | last session id, a fallback for hooks whose payload has none | 0600 |
| `~/.anamnesis/paused` | present ⇒ hooks exit 0 silently | 0600 |
| `~/.anamnesis/pending_uploads/*.json` | queued payloads from failed uploads; replayed in the background at the next SessionStart | 0600 |
| `~/.anamnesis/stop_state/` | per-transcript upload progress and locks | 0600 |
| `~/.anamnesis/receipt_state/` | receipt rate-limit markers + deferred capture-receipt outcome; swept at SessionEnd | 0600 |
| `~/.anamnesis/auth_failed` | present while the server is rejecting your sign-in | 0600 |
| `~/.anamnesis/hook_errors.log` | structured JSONL of errors — for debugging only | 0600 |

Modes are those the hooks create files with (they run under `umask 077`);
files left by older versions keep their mode. Nothing in
`.claude/settings.json` holds your credentials.

## Failure behavior

Hooks **never block Claude Code** and always exit 0. On a server error
they append a structured entry to `~/.anamnesis/hook_errors.log` and, for
an upload, queue the payload under `~/.anamnesis/pending_uploads/`. The
next `SessionStart` replays the queue in the background, stopping at the
first failure. When the server rejects your sign-in, Claude Code shows one
`[anamnesis]` warning line per session until `anamnesis-config` fixes it.

## Uninstall

```
/plugin uninstall anamnesis@smtry
rm -rf ~/.anamnesis   # optional — removes local config + queued uploads
```

Delete your server-side memory at `anamnesis.smtry.ai/memory` if you
want all traces gone — deletion removes the encrypted files from the
live store, and full account deletion is self-serve from the account
page.

## License

MIT. See [`LICENSE`](../../LICENSE).
