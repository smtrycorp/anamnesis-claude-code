# smtry — Claude Code marketplace

Plugins from [smtry.ai](https://anamnesis.smtry.ai) for Claude Code.

## Install

```
/plugin marketplace add https://github.com/smtrycorp/anamnesis-claude-code
/plugin install anamnesis@smtry
```

Then run `anamnesis-config` once to paste in your api_key and handle.

## Plugins

### anamnesis

Persistent, encrypted memory for Claude Code. Four lifecycle hooks
(`SessionStart`, `UserPromptSubmit`, `Stop`, `SessionEnd`) capture your
work deterministically — no reliance on the model choosing to call a
tool. Each user's memory is encrypted at rest under a per-user key
derived from their own api_key — no master key, so a bulk database
compromise alone decrypts nothing. Not yet end-to-end: client-held keys
are the roadmap, and
[anamnesis.smtry.ai/security](https://anamnesis.smtry.ai/security) says
exactly who can decrypt what. Browse, search, and delete any memory at
[anamnesis.smtry.ai/memory](https://anamnesis.smtry.ai/memory).

See [`plugins/anamnesis/README.md`](plugins/anamnesis/README.md) for
setup, privacy model, and hook details.

## License

MIT. See [`LICENSE`](LICENSE).
