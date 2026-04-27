#!/bin/bash
# Claude Code Starter — CLI Tools Installer
#
# Installs all external CLIs referenced by the agents/skills/commands in this repo.
# Idempotent: detects what's already installed, only installs what's missing.
#
# Tiers:
#   core      — required by CLAUDE.md mandatory rules (bd, gh, jq, node)
#   search    — code/doc search tools (ogrep, ripgrep)
#   browser   — browser automation (agent-browser via npm)
#   deploy    — deploy/cloud clients (wrangler, vercel, rclone)
#   media     — media tools used by avatar-video, nano-banana skills (ffmpeg)
#   optional  — codex, eas-cli, etc.
#
# Usage:
#   ./install-tools.sh              # install everything
#   ./install-tools.sh --core       # only core
#   ./install-tools.sh --check      # report what's missing, install nothing
#   ./install-tools.sh --skip-brew  # skip Homebrew bootstrap

set -u

TIER="all"
CHECK_ONLY=0
SKIP_BREW=0

for arg in "$@"; do
  case "$arg" in
    --core)      TIER="core" ;;
    --search)    TIER="search" ;;
    --browser)   TIER="browser" ;;
    --deploy)    TIER="deploy" ;;
    --media)     TIER="media" ;;
    --hud)       TIER="hud" ;;
    --optional)  TIER="optional" ;;
    --check)     CHECK_ONLY=1 ;;
    --skip-brew) SKIP_BREW=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

# Ensure common bin dirs are on PATH for detection
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; CYAN="\033[0;36m"; NC="\033[0m"
ok()    { echo -e "  ${GREEN}✓${NC} $*"; }
warn()  { echo -e "  ${YELLOW}!${NC} $*"; }
miss()  { echo -e "  ${RED}✗${NC} $*"; }
info()  { echo -e "${CYAN}==>${NC} $*"; }

have() { command -v "$1" >/dev/null 2>&1; }

run_or_show() {
  if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "    would run: $*"
    return 0
  fi
  echo "    + $*"
  eval "$@"
}

#─────────────────────────────────────────────────────────────────────────────
# Step 1: Homebrew (foundation for everything else on macOS)
#─────────────────────────────────────────────────────────────────────────────
ensure_brew() {
  [ "$SKIP_BREW" -eq 1 ] && { warn "skipping brew bootstrap (--skip-brew)"; return; }
  if have brew; then ok "brew $(brew --version | head -1)"; return; fi

  miss "brew not installed"
  if [ "$CHECK_ONLY" -eq 1 ]; then return; fi

  if [[ "$(uname)" != "Darwin" ]]; then
    warn "Homebrew is the macOS path; on Linux install tools via your package manager"
    return 1
  fi

  echo
  info "Installing Homebrew (will prompt for your macOS password)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  local rc=$?

  # Add brew to PATH for the rest of this script (Apple Silicon vs Intel)
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  if have brew; then
    ok "brew $(brew --version | head -1)"
    # Add brew to user's shell rc for future sessions
    local shellrc="$HOME/.zshrc"
    [ -n "${BASH_VERSION:-}" ] && shellrc="$HOME/.bash_profile"
    if [ -f "$shellrc" ] && ! grep -q "brew shellenv" "$shellrc" 2>/dev/null; then
      echo "" >> "$shellrc"
      echo '# Homebrew (added by claude-code-starter install-tools.sh)' >> "$shellrc"
      if [ -x /opt/homebrew/bin/brew ]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$shellrc"
      else
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$shellrc"
      fi
      ok "added brew to $shellrc"
    fi
    return 0
  else
    miss "Homebrew install failed (exit $rc)"
    echo
    echo "  Install manually with:"
    echo '    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    return 1
  fi
}

#─────────────────────────────────────────────────────────────────────────────
# Step 2: install via brew if missing
#─────────────────────────────────────────────────────────────────────────────
brew_install() {
  local pkg="$1" bin="${2:-$1}"
  if have "$bin"; then ok "$bin"; return; fi
  miss "$bin"
  have brew || { warn "brew not available — skip $pkg"; return; }
  run_or_show "brew install $pkg"
}

#─────────────────────────────────────────────────────────────────────────────
# Step 3: install npm globals (Node must be installed first)
#─────────────────────────────────────────────────────────────────────────────
npm_install() {
  local pkg="$1" bin="${2:-$1}"
  if have "$bin"; then ok "$bin"; return; fi
  miss "$bin"
  have npm || { warn "npm not available — install Node first (brew install node)"; return; }
  run_or_show "npm install -g $pkg"
}

#─────────────────────────────────────────────────────────────────────────────
# Step 4: install via cargo (Rust must be installed first)
#─────────────────────────────────────────────────────────────────────────────
cargo_install() {
  local pkg="$1" bin="${2:-$1}"
  if have "$bin"; then ok "$bin"; return; fi
  miss "$bin"
  have cargo || { warn "cargo not available — install Rust first (brew install rust)"; return; }
  run_or_show "cargo install $pkg"
}

#─────────────────────────────────────────────────────────────────────────────
# Tier installers
#─────────────────────────────────────────────────────────────────────────────
install_core() {
  info "Tier: core (mandatory per CLAUDE.md)"
  brew_install jq jq
  brew_install node node     # provides npm
  brew_install gh gh         # GitHub API rate limit rule
  # bd (beads) — task tracking
  if have bd; then
    ok "bd $(bd --version 2>/dev/null | head -1)"
  else
    miss "bd"
    have brew && run_or_show "brew install steveyegge/tap/beads" \
              || warn "install bd: see https://github.com/steveyegge/beads"
  fi
}

install_search() {
  info "Tier: search (code & doc search)"
  brew_install ripgrep rg
  # osgrep — Open Source Semantic Search (Ryandonofrio3/osgrep) — referenced as `ogrep` in CLAUDE.md
  npm_install osgrep osgrep
  # Symlink ogrep -> osgrep so CLAUDE.md `ogrep` commands work
  if have osgrep && ! have ogrep; then
    local link_path
    link_path="$(dirname "$(command -v osgrep)")/ogrep"
    if [ ! -e "$link_path" ]; then
      ln -sf "$(command -v osgrep)" "$link_path" && ok "linked ogrep -> osgrep"
    fi
  fi
  # qmd — tobi/qmd — local doc/notes semantic search (referenced in CLAUDE.md)
  npm_install @tobilu/qmd qmd
}

install_browser() {
  info "Tier: browser automation"
  npm_install agent-browser agent-browser
}

install_deploy() {
  info "Tier: deploy / cloud clients"
  brew_install rclone rclone
  npm_install wrangler wrangler
  npm_install vercel vercel
}

install_media() {
  info "Tier: media tools"
  brew_install ffmpeg ffmpeg
}

install_claude_hud() {
  info "Tier: claude-hud (statusLine HUD)"
  local hud_dir="$HOME/claude-hud"
  if [ -f "$hud_dir/dist/index.js" ]; then
    ok "claude-hud built at $hud_dir"
    return
  fi
  miss "claude-hud not built"
  if [ "$CHECK_ONLY" -eq 1 ]; then return; fi
  if ! have node; then
    warn "node required — install Node first (brew install node)"
    return 1
  fi
  if [ ! -d "$hud_dir" ]; then
    run_or_show "git clone https://github.com/barkleesanders/claude-hud.git $hud_dir"
  fi
  ( cd "$hud_dir" && run_or_show "npm install" && run_or_show "npm run build" )
  if [ -f "$hud_dir/dist/index.js" ]; then
    ok "claude-hud built"
  else
    miss "claude-hud build failed"
  fi
}

install_optional() {
  info "Tier: optional"
  npm_install eas-cli eas
  # codex CLI — referenced by codex-chat skill
  if have codex; then
    ok "codex"
  else
    warn "codex — install per skills/codex/SKILL.md (typically: npm install -g @openai/codex)"
  fi
  # asc — App Store Connect CLI (ios-ship)
  if have asc; then
    ok "asc"
  else
    warn "asc — App Store Connect CLI; install per skills/ios-ship/SKILL.md"
  fi
}

#─────────────────────────────────────────────────────────────────────────────
# Run
#─────────────────────────────────────────────────────────────────────────────
echo
[ "$CHECK_ONLY" -eq 1 ] && info "CHECK MODE — nothing will be installed"
ensure_brew

case "$TIER" in
  core)     install_core ;;
  search)   install_search ;;
  browser)  install_browser ;;
  deploy)   install_deploy ;;
  media)    install_media ;;
  optional) install_optional ;;
  hud)      install_claude_hud ;;
  all)
    install_core
    install_search
    install_browser
    install_deploy
    install_media
    install_claude_hud
    install_optional
    ;;
esac

echo
info "Done. Re-run with --check to see remaining gaps."
