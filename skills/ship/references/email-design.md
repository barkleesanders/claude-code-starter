# Branded email release gate

Applies to every deployed Cloudflare website that sends email, through a Worker
binding, HTTP provider, Gmail, scheduled task, or Pages Function. Run this on every
ship, even when the current diff does not modify email. Inventory bindings AND
source; absence of a send_email binding does not prove a site sends no mail.
For a fleet request enumerate live Workers, routes, Pages deployments and provider
integrations; record unavailable surfaces separately from confirmed non-senders.

Use editorial correspondence: warm paper, dark readable ink, generous spacing,
and the site's own accent and font stack. Read the site's current design tokens;
do not copy a stale email's colors. Convert unsupported website colors to sRGB.
Use presentation tables, inline fonts/colors on cells, a responsive maximum width,
and selectable codes. Preserve existing subject, plaintext, sender, recipient,
reply-to, attachments, consent, unsubscribe, expiry and retry behavior. Escape all
untrusted interpolations; do not add tracking scripts or pixels. Authentication
mail must not gain unsubscribe controls intended for subscription messages.

Each sending repo must maintain email-design.json (version 1) with brand, paper,
ink, accent, senders (source paths), tests (test paths), and command (argv array).
Run `node <skill-root>/ship/tools/email-design-check.mjs <repo>` as a blocking gate.
Missing/unreadable contracts are UNMEASURED and block; failed contracts/tests are
BAD and block. The tool validates declared coverage and runs tests; it does not
prove the inventory is exhaustive, visual quality, or inbox delivery. Review the
inventory against all source send seams before accepting its coverage.

Tests must capture final messages at the real send seams, verify the shared design
marker and escaped content, and preserve transport metadata. Include both auth and
notification variants, admin/custom messages, scheduled and alternate transports.
Exercise the known-bad missing-wrapper and unsafe-interpolation variants so the
gate is demonstrated to reject regressions. Wire these tests into the repository's
normal build/predeploy path, including skip-tests release shortcuts.

Render representative final payloads at 375px and desktop widths. Check legibility,
long names/URLs, selectable OTPs and clear actions. After deployment verify the
active Worker version and actual deployed source contains the template. A website
HTTP 200 cannot prove email design. Inbox delivery and client rendering need an
explicitly authorized real send; never label a local mock, static domain check,
or provider acceptance as inbox delivery. Do not send customer notifications,
create fake filings, or invite users solely to test a design without authorization.
