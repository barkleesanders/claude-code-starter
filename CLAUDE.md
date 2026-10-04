# Claude Code Starter Configuration

Use evidence before conclusions, preserve user work, and verify behavior before
calling a change complete. Track project work in the project's own task system.

## Git safety

Run `git status` before state-changing Git commands. Never reset, clean, force
push, or overwrite unrelated work without explicit approval.

## Engineering workflow

- Use `/carmack` for implementation and evidence-based debugging.
- Use `/debug` for a structured root-cause investigation.
- Use `/ship` only when the user authorizes deployment.
- Keep fixes minimal and add regression coverage for corrected behavior.

## Public configuration boundary

This starter intentionally excludes personal, case-specific, health, benefits,
legal-advocacy, credentials, browser state, and machine-local configuration.
