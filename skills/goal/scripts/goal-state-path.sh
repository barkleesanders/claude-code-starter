#!/usr/bin/env bash
# goal-state-path.sh — the ONE resolver for where a goal's state lives.
#
# Sourced by goal.sh, goal-injector.sh, and goal-completion-stop-check.sh so the
# three can never drift. Before 2026-07-29 each file re-implemented
# `sha256(cwd) | cut -c1-16` on its own, which is exactly how the bug below
# survived a partial fix.
#
# THE BUG THIS FIXES (2026-07-29)
#   State was keyed by cwd ALONE. Every Claude session launched from the same
#   directory — nearly always $HOME — shared one goal slot. Session A could set a
#   goal on NYC transit fares while session B worked on disability benefits, and
#   B's stop hook would refuse to let B finish until A's unrelated goal was
#   "complete". An earlier patch added `warn_concurrent_session` + session
#   stamping, which DETECTED the collision but never prevented it: the warning
#   told you another session owned the goal while the hook kept gating you on it.
#   Detection is not isolation.
#
# THE SCHEME
#   session-scoped : <cwd16>--<sess8>.json     ← all goals created from now on
#   legacy/shared  : <cwd16>.json              ← goals created before this change
#
#   Lookup order, for a given (cwd, session):
#     1. the session-scoped file, if it exists                    → yours
#     2. the legacy file, ONLY if it is unowned or owned by you   → back-compat
#     3. the same two checks walking up the parent directories
#     4. otherwise the session-scoped path (so callers get a clean "not found")
#
#   Step 2 is the actual fix: a legacy goal owned by a DIFFERENT live session is
#   skipped, so it stops gating you — while remaining fully visible to the
#   session that owns it, and to everyone if it predates session stamping.
#
# STABILITY NOTE
#   Scoping is only safe because CLAUDE_CODE_SESSION_ID is a real, stable UUID
#   for the life of a session (verified 2026-07-29: identical across repeated
#   invocations). The pid-based fallback is NOT stable across invocations, so
#   when no session id is exported we deliberately fall back to LEGACY (shared)
#   behaviour rather than minting a new slot on every call.

goal_state_dir() {
  printf '%s' "${CLAUDE_GOAL_STATE_DIR:-$HOME/.claude/state/goal}"
}

# Resolved cwd, so /private/var vs /var don't produce two different keys.
goal_resolve_cwd() {
  local c="${1:-${CLAUDE_GOAL_CWD_OVERRIDE:-$PWD}}"
  (cd "$c" 2>/dev/null && pwd -P) || printf '%s' "$c"
}

goal_cwd_hash() {
  printf '%s' "$(goal_resolve_cwd "${1:-}")" | shasum -a 256 | cut -c1-16
}

# Real session id, or empty when none is exported. Empty means "use legacy
# shared behaviour" — never invent an unstable per-invocation id.
goal_session_id() {
  printf '%s' "${CLAUDE_GOAL_SESSION_OVERRIDE:-${CLAUDE_CODE_SESSION_ID:-${CLAUDE_CODE_BRIDGE_SESSION_ID:-}}}"
}

goal_session_hash() {
  local s="${1:-$(goal_session_id)}"
  [ -z "$s" ] && return 0
  printf '%s' "$s" | shasum -a 256 | cut -c1-8
}

# Is this state file readable by the given session?
# Yes when: it records no owner (predates stamping), or the owner is us.
goal_state_is_visible() {
  local sf="$1" sess="${2:-$(goal_session_id)}" owner
  [ -f "$sf" ] || return 1
  owner="$(python3 -c "
import json,sys
try:
    print(json.load(open(sys.argv[1])).get('session') or '')
except Exception:
    print('')
" "$sf" 2>/dev/null)"
  [ -z "$owner" ] && return 0        # unowned → shared, back-compat
  [ -z "$sess" ] && return 0         # we have no id → don't hide anything
  [ "$owner" = "$sess" ]             # owned → only the owner sees it
}

# goal_state_file [mode] [cwd] [session_id]
#   mode: lookup (default) | exact
# `exact` is for `set`: always the session-scoped path for THIS cwd, so a new
# goal never lands in a slot another session is using.
goal_state_file() {
  local mode="${1:-lookup}" cwd="${2:-}" sess="${3:-$(goal_session_id)}"
  local dir; dir="$(goal_state_dir)"
  local ch; ch="$(goal_cwd_hash "$cwd")"
  local sh; sh="$(goal_session_hash "$sess")"

  local scoped legacy
  if [ -n "$sh" ]; then scoped="$dir/${ch}--${sh}.json"; else scoped="$dir/${ch}.json"; fi
  legacy="$dir/${ch}.json"

  if [ "$mode" = "exact" ]; then printf '%s' "$scoped"; return 0; fi
  [ -f "$scoped" ] && { printf '%s' "$scoped"; return 0; }
  if goal_state_is_visible "$legacy" "$sess"; then printf '%s' "$legacy"; return 0; fi

  # Walk up the ancestor chain, same two checks at each level.
  local d; d="$(goal_resolve_cwd "$cwd")"
  while [ -n "$d" ]; do
    local h; h=$(printf '%s' "$d" | shasum -a 256 | cut -c1-16)
    if [ -n "$sh" ] && [ -f "$dir/${h}--${sh}.json" ]; then printf '%s' "$dir/${h}--${sh}.json"; return 0; fi
    if goal_state_is_visible "$dir/${h}.json" "$sess"; then printf '%s' "$dir/${h}.json"; return 0; fi
    [ "$d" = "/" ] && break
    local parent; parent=$(dirname "$d")
    [ "$parent" = "$d" ] && break
    d="$parent"
  done
  printf '%s' "$scoped"
}

# The LIFO stack that sits beside a given state file.
goal_stack_file() {
  local sf="${1:-$(goal_state_file)}"
  printf '%s' "${sf%.json}.stack.json"
}
