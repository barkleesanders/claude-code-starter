# Claude Code Starter

A portable, privacy-screened Claude Code configuration with reusable engineering
skills, specialist agents, and slash commands.

## Install

```bash
git clone https://github.com/barkleesanders/claude-code-starter.git
cd claude-code-starter
./install.sh
```

The installer copies the curated public files into `~/.claude`. It does not
overwrite an existing `CLAUDE.md` unless you explicitly choose to replace it.

Personal and case-specific skills are intentionally kept in a separate private
repository and are never generated into this public repository.

## Task tracking with beads

This starter assumes [beads](https://github.com/steveyegge/beads) (`bd`), a
Dolt-backed issue tracker built for AI coding agents. See [BEADS.md](BEADS.md)
for install and the daily commands. The standing rule: every task gets a bead,
and a bead closes only with cited evidence.
