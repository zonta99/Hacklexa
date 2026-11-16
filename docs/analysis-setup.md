# Analysis setup (REA + Ghidra)

The decompilation phase uses [REA](https://github.com/morluto/rea) driving Ghidra.
Recorded here so the environment is reproducible.

## Installed

| Tool | Version | How |
|---|---|---|
| REA (`rea-agents`) | 6.9.0 | `npm i -g rea-agents` (global, stable path) |
| Ghidra | 12.2 | `brew install ghidra` → `/opt/homebrew/opt/ghidra/libexec` |
| Temurin JDK | 21.0.13 | `brew install openjdk@21` (keg-only; no sudo) |

Ghidra's own bottle also pulls `openjdk@25`; REA's provider check passes against
12.2 (headless + native decompiler, darwin/arm64).

## REA MCP registration (Claude Code)

`rea setup --client claude_code --yes` adds an `rea` entry to `~/.claude.json` and
installs the `reverse-engineer-anything` skill under `~/.claude/skills/`. The entry
was repointed to the stable global binary so an `npx` cache purge can't break it:

```json
"rea": {
  "command": "/opt/homebrew/bin/rea",
  "args": ["mcp"],
  "env": {
    "GHIDRA_INSTALL_DIR": "/opt/homebrew/opt/ghidra/libexec",
    "JAVA_HOME": "/opt/homebrew/opt/openjdk@21"
  }
}
```

Backups: `~/.claude.json.rea.backup`, `~/.claude.json.hacklexa.bak`.

**The `rea` MCP server loads at Claude Code startup — restart the agent after setup
before the `mcp__rea__*` tools are available.**

## Analysis order

1. `aceipc-daemon` — the on-device IPC bus (the LIPC equivalent). Map the transport first.
2. `libAlexa.so` + `AlexaHybridExecutionControllerLitespeed` — the Alexa engine.
3. `amzn_dha_tool` / `libacehal_dha.so` — device-health attestation (diff against biscuit).
4. Boot chain (`lk.img`, `tee1/2.img`) — cross-check cgarrot rather than redo.

Targets live under `extract/system/system/{bin,lib}/` (git-ignored).
