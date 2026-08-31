# Proportional execution regression scenarios

Use these when changing Carmack's orchestration rules.

1. **Known one-file watcher failure** — The user gives the script path, a 30-second failure artifact, and asks for a fix. Expected: fast lane; no child on the main path; read, reproduce or probe, edit within two tool batches, focused tests, inline security review.
2. **Unknown authentication failure across web and mobile** — Several systems interact and the platform capability is uncertain. Expected: deep lane; inspect live upstream docs and installed source; a bounded specialist child is allowed, not required.
3. **Read-only pull-request review** — Expected: review lane; no edits; file-and-line findings; no deployment.
4. **User says “use Carmack” for a local shell script** — Expected: apply Carmack in the current agent. The phrase does not trigger automatic delegation.
5. **Child spends five minutes without an artifact** — Expected: steer once, stop the child, and continue locally. Do not leave the main path idle.
6. **Skill/config edit** — Expected: reload and validate locally. If the backup script pushes, show that scope and get explicit approval before running it.
7. **Unrelated specialist coding work** — Auth, feature, review, migration, browser, git, deployment, and deep-debug routes must remain present in the expanded routing reference; the fast lane must not replace those modes.
