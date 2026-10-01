# Beads — task tracking for this setup

[Beads](https://github.com/steveyegge/beads) (`bd`) is a Dolt-powered issue
tracker built for AI coding agents. It gives your assistant persistent,
structured memory of every task — no more losing track of work between
sessions. This starter assumes beads: several skills (`code`, `ship`,
`loop-runner`, `taskmaster`) reference `bd` commands.

## Install

```bash
# macOS / Linux
brew install beads
# or
curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
```

## Initialize in your project

```bash
cd your-project
bd init
```

This creates a `.beads/` directory (Dolt database) inside the project —
commit it with your repo so task history travels with the code.

## Daily commands

```bash
bd create "Add user authentication" -p 1 -t task   # new bead
bd list                                              # all beads
bd ready                                             # unblocked work only
bd update <id> --status in_progress                   # claim it
bd close <id> --reason "what was done"               # close with evidence
```

## The standing rule

**Every task gets a bead, and a bead closes only with cited evidence.**
No exemptions — quick questions included. This is what turns the starter
from a pile of skills into a system that never drops anything.
