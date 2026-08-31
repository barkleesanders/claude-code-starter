---
name: routerctl
description: Use when managing the user's local Xfinity router, DHCP reservations, printer/Mac LAN stability, firewall/Wi-Fi/DMZ/remote-management audits, or dry-running router actionHandler endpoints through the routerctl CLI.
---

# routerctl

Use `routerctl` for the user's local Xfinity router. It logs into `10.0.0.1`, probes pages, discovers AJAX endpoints, and performs safe device reservations.

## First Rules

- Do not print router credentials.
- Prefer `routerctl` over custom Playwright scripts.
- Use `routerctl pages`, `inspect`, and `endpoints` before changing settings.
- `routerctl action` is dry-run by default. Only pass `--confirm` when the user intentionally requests the mutation.
- For risky areas, dry-run first: firewall, Wi-Fi, reset/restore, DMZ, and remote management.
- Leave Zero Config disabled unless explicitly troubleshooting Bonjour/AirPrint discovery.
- After any change, verify the affected page plus `routerctl audit --json`.

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

## Known Stable Reservations

- Printer: `DELL5F4BDD`, `10.0.0.200`, `3C:A0:67:5F:4B:DD`
- MacBook: `Mac`, `10.0.0.132`, `AA:A2:65:54:21:2F`
- Mac mini: `the users-Mini`, `10.0.0.213`, `1C:F6:4C:52:E5:1F`

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
routerctl find --ip 10.0.0.213 --json
routerctl find --ip 10.0.0.200 --json
routerctl audit --json
```
