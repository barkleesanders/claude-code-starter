---
name: routerctl
description: Use when managing the user's local Xfinity router, DHCP reservations, printer/Mac LAN stability, firewall/Wi-Fi/DMZ/remote-management audits, or dry-running router actionHandler endpoints through the routerctl CLI.
---

# routerctl

Use `routerctl` for the user's local Xfinity router. It logs into `10.0.0.1`, probes pages, discovers AJAX endpoints, and performs safe device reservations.

## First Rules

- Do not print router credentials.
- Prefer `routerctl` over custom Playwright scripts. `routerctl` logs into `http://10.0.0.1` with an HTTP cookie session (Chrome blocks that host with `ERR_BLOCKED_BY_CLIENT`). It still fills the local admin password from `~/router_login_working.js`. Set `ROUTERCTL_DRIVER=fcdp` only if you need the real Chrome path.
- Use `routerctl pages`, `inspect`, and `endpoints` before changing settings.
- `routerctl action` is dry-run by default. Only pass `--confirm` when the user intentionally requests the mutation.
- For risky areas, dry-run first: firewall, Wi-Fi, reset/restore, DMZ, and remote management.
- Leave Zero Config disabled unless explicitly troubleshooting Bonjour/AirPrint discovery.
- After any change, verify the affected page plus `routerctl audit --json`.

## Interpret evidence before acting

- Discovery has three states: `enabled`, `disabled`, and `unknown`. Use
  `upnpState` and `zeroconfigState`; legacy boolean fields are `null` when unknown.
  Never coerce missing values, parse failures, or unrecognized controls to disabled.
- Require `complete: true` for a complete discovery result. `ok: false` or a nonzero
  exit requires inspecting the errors and source, even when partial results exist.
- `pages` and `endpoints` can return partial results. Check their errors and each
  page outcome before claiming a complete inventory or that an endpoint is absent.
- Current gateway discovery switches initialize from `jsEnableUPnP` and
  `jsEnableZero` in the authenticated page's JavaScript. Older firmware may use
  checked radio controls. Parse explicit evidence without executing remote scripts;
  missing, malformed, or conflicting evidence stays unknown.
- Capture a sanitized live page fixture when firmware markup changes. Remove
  passwords, cookies, tokens, public addresses, and device identifiers. Test the
  captured markup plus missing and conflicting signals before trusting a repair.
- Verify the active device's IP and MAC against both the router and the device
  before reserving it. Historical names and reservations are lookup hints only.

## Diagnose access separately from router health

If `routerctl` returns `EHOSTUNREACH` or the browser blocks the admin page,
compare a direct HTTP probe and gateway ping from the same Mac. Check from
`ssh mini-lan` when available. A failure in one runtime does not establish a
router outage. Use `ROUTERCTL_DRIVER=http` to isolate HTTP diagnostics from the
browser fallback. Report the access limitation explicitly; do not weaken firewall
or macOS permissions, reboot the gateway, or interpret failed reads as disabled
settings. Keep credentials out of command arguments and diagnostic output.

## Common Commands

```bash
routerctl list --json
routerctl find --ip 10.0.0.132 --json
routerctl reserve --ip 10.0.0.132 --mac AA:A2:65:54:21:2F --json
routerctl discovery --json
routerctl audit --json
routerctl pages --json
routerctl inspect device_discovery.jst --json
routerctl endpoints --json
```

## Previously observed reservations — reverify before use

- Printer: `DELL5F4BDD`, `10.0.0.200`, `3C:A0:67:5F:4B:DD`
- MacBook: `Mac`, `10.0.0.132`, `AA:A2:65:54:21:2F`
- Mac mini older interface: `the users-Mini`, `10.0.0.213`, `1C:F6:4C:52:E5:1F`
- Mac mini active Wi-Fi observed 2026-09-13: `10.0.0.150`, `92:9B:67:C5:6C:1D`.
  This reservation follows that MAC; reverify if private Wi-Fi addressing changes.

## Dry-Run Risky Controls

Run these without `--confirm` unless the user explicitly wants the change applied:

```bash
routerctl action actionHandler/ajaxSet_firewall_config.jst --page firewall_settings_ipv4.jst --data-json '{"configInfo":"dry-run-noop-firewall-ipv4"}' --json
routerctl action actionHandler/ajaxSet_firewall_config_v6.jst --page firewall_settings_ipv6.jst --data-json '{"configInfo":"dry-run-noop-firewall-ipv6"}' --json
routerctl action actionHandler/ajaxSet_wireless_network_configuration.jst --page wireless_network_configuration.jst --data-json '{"configInfo":"dry-run-noop-wifi"}' --json
routerctl action actionHandler/ajaxSet_DMZ_configuration.jst --page dmz.jst --data-json '{"configInfo":"dry-run-noop-dmz"}' --json
routerctl action actionHandler/ajax_remote_management.jst --page remote_management.jst --data-json '{"configInfo":"dry-run-noop-remote-management"}' --json
routerctl action actionHandler/ajaxSet_Reset_Restore.jst --page restore_reboot.jst --data-json '{"configInfo":"dry-run-noop-reset-restore"}' --json
```

## Verification Pattern

```bash
routerctl discovery --json
routerctl find --ip 10.0.0.132 --json
routerctl find --ip 10.0.0.150 --json
routerctl find --ip 10.0.0.213 --json
routerctl find --ip 10.0.0.200 --json
routerctl audit --json
```
