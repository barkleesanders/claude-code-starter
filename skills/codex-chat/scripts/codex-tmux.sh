#!/usr/bin/env bash
# codex-tmux.sh — Bridge between Claude Code and Codex CLI via tmux
# Usage:
#   codex-tmux.sh start [--model MODEL] [--cd DIR]   Start a Codex session in tmux
#   codex-tmux.sh send "prompt"                       Send a prompt to the running session
#   codex-tmux.sh read                                Read latest output from the session
#   codex-tmux.sh wait [TIMEOUT_SEC]                  Wait for Codex to finish responding
#   codex-tmux.sh ask "prompt" [TIMEOUT_SEC]          Send + wait + read (all-in-one)
#   codex-tmux.sh status                              Check if session is alive
#   codex-tmux.sh stop                                Kill the session
#   codex-tmux.sh exec "prompt" [-o FILE]             One-shot: run codex exec (no tmux)

set -euo pipefail

SESSION_NAME="codex-bridge"
OUTPUT_DIR="/tmp/codex-bridge"
OUTPUT_FILE="$OUTPUT_DIR/output.txt"
PROMPT_FILE="$OUTPUT_DIR/prompt.txt"
STATUS_FILE="$OUTPUT_DIR/status.txt"
LOG_FILE="$OUTPUT_DIR/session.log"

mkdir -p "$OUTPUT_DIR"

# ──────────────────────────────────────
# Helpers
# ──────────────────────────────────────

session_exists() {
  tmux has-session -t "$SESSION_NAME" 2>/dev/null
}

capture_pane() {
  # Capture the full scrollback buffer
  tmux capture-pane -t "$SESSION_NAME" -p -S - 2>/dev/null
}

wait_for_idle() {
  local timeout="${1:-120}"
  local interval=2
  local elapsed=0
  local prev_len=0
  local stable_count=0

  echo "waiting" > "$STATUS_FILE"

  while [ "$elapsed" -lt "$timeout" ]; do
    sleep "$interval"
    elapsed=$((elapsed + interval))

    # Capture current output length
    local current
    current=$(capture_pane | wc -c | tr -d ' ')

    if [ "$current" = "$prev_len" ] && [ "$current" -gt 0 ]; then
      stable_count=$((stable_count + 1))
      # Output hasn't changed for 3 consecutive checks (6 seconds) = done
      if [ "$stable_count" -ge 3 ]; then
        echo "idle" > "$STATUS_FILE"
        return 0
      fi
    else
      stable_count=0
    fi
    prev_len="$current"
  done

  echo "timeout" > "$STATUS_FILE"
  return 1
}

# ──────────────────────────────────────
# Commands
# ──────────────────────────────────────

cmd_start() {
  local model=""
  local workdir=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model) model="$2"; shift 2 ;;
      --cd) workdir="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if session_exists; then
    echo "[codex-tmux] Session '$SESSION_NAME' already running. Use 'stop' first to restart."
    return 0
  fi

  # Build codex command
  local cmd="codex"
  [ -n "$model" ] && cmd="$cmd -m $model"
  [ -n "$workdir" ] && cmd="$cmd -C $workdir"

  # Start tmux session with codex interactive mode
  tmux new-session -d -s "$SESSION_NAME" -x 200 -y 50 "$cmd"

  # Give it a moment to initialize
  sleep 3

  echo "[codex-tmux] Session started. Codex is ready for prompts."
  echo "running" > "$STATUS_FILE"
}

cmd_send() {
  local prompt="$1"

  if ! session_exists; then
    echo "[codex-tmux] No active session. Run 'start' first."
    return 1
  fi

  # Save prompt for reference
  echo "$prompt" > "$PROMPT_FILE"

  # Clear previous output marker
  echo "" > "$OUTPUT_FILE"

  # Send the prompt text to the tmux pane
  # Use send-keys with literal flag to handle special chars
  tmux send-keys -t "$SESSION_NAME" -l "$prompt"
  # Send Enter to submit
  tmux send-keys -t "$SESSION_NAME" Enter

  echo "[codex-tmux] Prompt sent."
}

cmd_read() {
  if ! session_exists; then
    echo "[codex-tmux] No active session."
    return 1
  fi

  capture_pane
}

cmd_wait() {
  local timeout="${1:-120}"

  if ! session_exists; then
    echo "[codex-tmux] No active session."
    return 1
  fi

  if wait_for_idle "$timeout"; then
    echo "[codex-tmux] Codex appears idle (output stable for 6s)."
  else
    echo "[codex-tmux] Timed out after ${timeout}s waiting for Codex to finish."
    return 1
  fi
}

cmd_ask() {
  local prompt="$1"
  local timeout="${2:-120}"

  cmd_send "$prompt"
  sleep 2  # Brief pause before we start monitoring
  cmd_wait "$timeout"
  echo ""
  echo "--- Codex Response ---"
  capture_pane | tail -n +2  # Skip the first line (usually the prompt echo)
}

cmd_status() {
  if session_exists; then
    echo "[codex-tmux] Session '$SESSION_NAME' is running."
    echo "[codex-tmux] Status: $(cat "$STATUS_FILE" 2>/dev/null || echo 'unknown')"
    echo "[codex-tmux] Last prompt: $(cat "$PROMPT_FILE" 2>/dev/null || echo 'none')"
  else
    echo "[codex-tmux] No active session."
  fi
}

cmd_stop() {
  if session_exists; then
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null
    echo "[codex-tmux] Session stopped."
    echo "stopped" > "$STATUS_FILE"
  else
    echo "[codex-tmux] No active session to stop."
  fi
}

cmd_exec() {
  # One-shot mode: codex exec with --full-auto
  local prompt=""
  local output_file="/tmp/codex-bridge/exec-reply.txt"
  local model=""
  local workdir=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o) output_file="$2"; shift 2 ;;
      -m|--model) model="$2"; shift 2 ;;
      -C|--cd) workdir="$2"; shift 2 ;;
      *) prompt="$1"; shift ;;
    esac
  done

  if [ -z "$prompt" ]; then
    echo "[codex-exec] No prompt provided."
    return 1
  fi

  local cmd="codex exec --sandbox workspace-write"
  [ -n "$model" ] && cmd="$cmd -m $model"
  [ -n "$workdir" ] && cmd="$cmd -C $workdir"
  cmd="$cmd -o $output_file"

  echo "[codex-exec] Sending to Codex (exec mode)..."
  echo "$prompt" | eval "$cmd" 2>&1

  if [ -f "$output_file" ]; then
    echo ""
    echo "--- Codex Reply ---"
    cat "$output_file"
  else
    echo "[codex-exec] No output file generated."
  fi
}

# ──────────────────────────────────────
# Dispatch
# ──────────────────────────────────────

case "${1:-help}" in
  start)  shift; cmd_start "$@" ;;
  send)   shift; cmd_send "$*" ;;
  read)   cmd_read ;;
  wait)   shift; cmd_wait "${1:-120}" ;;
  ask)    shift; cmd_ask "$1" "${2:-120}" ;;
  status) cmd_status ;;
  stop)   cmd_stop ;;
  exec)   shift; cmd_exec "$@" ;;
  help|*)
    echo "codex-tmux.sh — Bridge between Claude Code and Codex CLI"
    echo ""
    echo "Commands:"
    echo "  start [--model M] [--cd DIR]   Start interactive Codex session in tmux"
    echo "  send \"prompt\"                   Send a prompt to the running session"
    echo "  read                            Read current output from the session"
    echo "  wait [TIMEOUT]                  Wait for Codex to stop outputting"
    echo "  ask \"prompt\" [TIMEOUT]          Send + wait + read (all-in-one)"
    echo "  status                          Check session status"
    echo "  stop                            Kill the session"
    echo "  exec \"prompt\" [-o FILE]         One-shot (no tmux, codex exec --full-auto)"
    ;;
esac
