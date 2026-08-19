---
name: pake
user-invocable: true
description: >
  Turn any webpage into a lightweight desktop app (~5MB) using Rust/Tauri. Use when the user
  wants to create a desktop app from a URL, package a web app as a native app, or build a
  lightweight Electron alternative. Triggers on: "make a desktop app from", "package this site",
  "pake", "/pake", "turn this into a desktop app", "wrap this URL".
---

# /pake — Web-to-Desktop App Packager

Pake turns any webpage into a native desktop app using Rust/Tauri. ~5MB output vs ~150MB for Electron.

## Quick Start

```bash
# Basic — just a URL and a name
pake https://example.com --name MyApp

# With custom icon and window size
pake https://weekly.tw93.fun --name Weekly --icon ./icon.icns --width 1200 --height 800

# Frameless Mac app (hidden title bar)
pake https://chat.openai.com --name ChatGPT --hide-title-bar

# Full screen app
pake https://youtube.com --name YouTube --fullscreen

# Universal Mac binary (Intel + Apple Silicon)
pake https://example.com --name MyApp --multi-arch
```

## All Options

| Flag | Description |
|------|-------------|
| `--name <string>` | Application name |
| `--icon <string>` | App icon path (`.icns` for Mac, `.ico` for Windows, `.png` for Linux) |
| `--width <number>` | Window width in pixels |
| `--height <number>` | Window height in pixels |
| `--fullscreen` | Launch in fullscreen mode |
| `--hide-title-bar` | macOS: frameless window with traffic lights |
| `--multi-arch` | macOS: build universal binary (Intel + M1) |
| `--use-local-file` | Package a local HTML file instead of a URL |
| `--inject <files>` | Inject local CSS/JS files into the page |
| `--debug` | Debug build with extra output |
| `--targets <string>` | Cross-compile target format |

## Inject Custom CSS/JS

Create custom styles or scripts and inject them:

```bash
# Inject custom CSS to restyle the app
echo "body { font-family: 'SF Pro' !important; }" > custom.css
pake https://example.com --name MyApp --inject custom.css

# Inject JS to add functionality
echo "console.log('Pake app loaded');" > init.js
pake https://example.com --name MyApp --inject custom.css,init.js
```

## Local HTML Apps

Package a local HTML file as a desktop app:

```bash
pake ./index.html --name MyApp --use-local-file
```

## Prerequisites

Pake requires Rust and system build tools:

```bash
# macOS
xcode-select --install  # Xcode command line tools
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh  # Rust

# Verify
rustc --version
```

If Rust is not installed, Pake will prompt to install it.

## Output

The built app appears in the current directory as:
- macOS: `MyApp.app` (inside a `.dmg`)
- Windows: `MyApp_x64.msi`
- Linux: `MyApp.AppImage` or `.deb`

## Instructions

When this skill is invoked:

1. Confirm the URL and desired app name with the user
2. Check if Rust is installed (`rustc --version`), install if needed
3. Run `pake <url> --name <name>` with any requested options
4. The first build takes longer (compiling Rust/Tauri); subsequent builds are faster
5. Report the output file location when done
