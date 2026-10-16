# shellcheck shell=bash
# UI helpers: colors, progress bar, spinner, prompts and the final summary.
# Bash 3.2 compatible (the bash that ships with macOS).

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_MAGENTA=$'\033[35m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""
  C_BLUE=""; C_MAGENTA=""; C_CYAN=""
fi

SUMMARY_OK=()
SUMMARY_SKIP=()
SUMMARY_FAIL=()
SUMMARY_MANUAL=()

info()    { printf '%s  ›%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()      { printf '%s  ✔%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()    { printf '%s  !%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()     { printf '%s  ✘%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
log()     { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG_FILE"; }

record_ok()     { SUMMARY_OK+=("$1"); log "OK: $1"; }
record_skip()   { SUMMARY_SKIP+=("$1"); log "SKIP: $1"; }
record_fail()   { SUMMARY_FAIL+=("$1"); log "FAIL: $1"; }
record_manual() { SUMMARY_MANUAL+=("$1"); log "MANUAL: $1"; }

have() { command -v "$1" >/dev/null 2>&1; }
have_gum() { have gum && [ -z "${BOOT_NO_GUM:-}" ]; }

# ── Progress bar ─────────────────────────────────────────────────────────────
# progress_bar <current> <total> <label>
progress_bar() {
  local cur=$1 total=$2 label=$3 width=36
  local filled=$(( cur * width / total ))
  local empty=$(( width - filled ))
  local pct=$(( cur * 100 / total ))
  local bar="" i
  for (( i = 0; i < filled; i++ )); do bar="${bar}█"; done
  for (( i = 0; i < empty; i++ )); do bar="${bar}░"; done
  if [ "$cur" -ge "$total" ] && [ "$label" = "All done" ]; then
    printf '\n%s%s━━━ All done ━━━%s\n' "$C_BOLD" "$C_MAGENTA" "$C_RESET"
  else
    printf '\n%s%s━━━ Step %d/%d ━━━ %s%s\n' "$C_BOLD" "$C_MAGENTA" "$cur" "$total" "$label" "$C_RESET"
  fi
  printf '%s%s%s %3d%%\n\n' "$C_CYAN" "$bar" "$C_RESET" "$pct"
}

# ── Spinner ──────────────────────────────────────────────────────────────────
# run "<description>" cmd args...   → runs the command with a spinner, output
# goes to the log. Returns the command's exit code. On failure prints the
# last lines of output.
run() {
  local desc=$1; shift
  log "RUN: $desc :: $*"
  if [ -n "${DRY_RUN:-}" ]; then
    printf '%s  ⋯%s %s %s(dry-run: %s)%s\n' "$C_DIM" "$C_RESET" "$desc" "$C_DIM" "$*" "$C_RESET"
    return 0
  fi
  local tmp; tmp=$(mktemp -t bootmymac)
  ( "$@" ) >"$tmp" 2>&1 &
  local pid=$! i=0 start=$SECONDS
  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  if [ -t 1 ]; then
    while kill -0 "$pid" 2>/dev/null; do
      local el=$(( SECONDS - start ))
      printf '\r  %s%s%s %s %s(%dm%02ds)%s ' "$C_CYAN" "${frames[i % 10]}" "$C_RESET" "$desc" "$C_DIM" $((el / 60)) $((el % 60)) "$C_RESET"
      i=$((i + 1))
      sleep 0.15
    done
  fi
  wait "$pid"; local rc=$?
  cat "$tmp" >>"$LOG_FILE"
  [ -t 1 ] && printf '\r\033[K'
  if [ $rc -eq 0 ]; then
    ok "$desc"
  else
    err "$desc (exit $rc)"
    tail -n 15 "$tmp" | sed 's/^/      /' >&2
  fi
  rm -f "$tmp"
  return $rc
}

# run_fg "<description>" cmd...  → runs in the foreground (for interactive commands)
run_fg() {
  local desc=$1; shift
  log "RUN_FG: $desc :: $*"
  if [ -n "${DRY_RUN:-}" ]; then
    printf '%s  ⋯%s %s %s(dry-run: %s)%s\n' "$C_DIM" "$C_RESET" "$desc" "$C_DIM" "$*" "$C_RESET"
    return 0
  fi
  info "$desc"
  "$@"; local rc=$?
  if [ $rc -eq 0 ]; then ok "$desc"; else err "$desc (exit $rc)"; fi
  return $rc
}

# ── Prompts (gum when available, plain read otherwise) ───────────────────────
# ask_yn "question" [default y|n]  → returns 0 for yes
ask_yn() {
  local q=$1 def=${2:-y}
  if [ -n "${BOOT_ASSUME_DEFAULTS:-}" ]; then [ "$def" = y ]; return; fi
  if have_gum; then
    if [ "$def" = y ]; then gum confirm --default=true "$q" </dev/tty; else gum confirm --default=false "$q" </dev/tty; fi
    return
  fi
  local hint="[Y/n]"; [ "$def" = n ] && hint="[y/N]"
  local ans
  read -r -p "  ? $q $hint " ans </dev/tty
  ans=${ans:-$def}
  case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# ask_input "prompt" [default]  → prints the answer
ask_input() {
  local q=$1 def=${2:-}
  if [ -n "${BOOT_ASSUME_DEFAULTS:-}" ]; then printf '%s\n' "$def"; return; fi
  if have_gum; then
    gum input --prompt "? $q: " --value "$def" --width 90 </dev/tty
    return
  fi
  local ans
  read -r -p "  ? $q [$def]: " ans </dev/tty
  printf '%s\n' "${ans:-$def}"
}

# choose_many "header" "preselected,comma,list|*|" item1 item2 ...
# Prints one selected item per line. "*" preselects all, "" none.
choose_many() {
  local header=$1 pre=$2; shift 2
  [ $# -eq 0 ] && return 0
  if [ -n "${BOOT_ASSUME_DEFAULTS:-}" ]; then
    local it
    for it in "$@"; do
      if [ "$pre" = "*" ] || case ",$pre," in *",$it,"*) true ;; *) false ;; esac; then
        printf '%s\n' "$it"
      fi
    done
    return
  fi
  if have_gum; then
    local args=(--no-limit --header "$header (x or tab = toggle, enter = confirm)" --height 20)
    if [ "$pre" = "*" ]; then args+=(--selected "*"); elif [ -n "$pre" ]; then args+=(--selected "$pre"); fi
    if [ $# -gt 15 ]; then
      # Long lists get a fuzzy filter so you can type to search.
      local fargs=(--no-limit --header "$header (type to search, tab = toggle, enter = confirm)" --height 20 --placeholder "search…")
      printf '%s\n' "$@" | gum filter "${fargs[@]}"
    else
      gum choose "${args[@]}" "$@" </dev/tty
    fi
    return
  fi
  # Plain fallback: numbered list.
  local i=1 it
  printf '\n  %s%s%s\n' "$C_BOLD" "$header" "$C_RESET" >/dev/tty
  for it in "$@"; do printf '   %2d) %s\n' "$i" "$it" >/dev/tty; i=$((i + 1)); done
  local ans
  read -r -p "  Numbers separated by space (a = all, empty = none): " ans </dev/tty
  if [ "$ans" = a ]; then printf '%s\n' "$@"; return; fi
  local n
  for n in $ans; do
    case "$n" in *[!0-9]*) continue ;; esac
    [ "$n" -ge 1 ] && [ "$n" -le $# ] && eval "printf '%s\n' \"\${$n}\""
  done
}

# choose_one "header" item1 item2 ...
choose_one() {
  local header=$1; shift
  if [ -n "${BOOT_ASSUME_DEFAULTS:-}" ]; then printf '%s\n' "$1"; return; fi
  if have_gum; then gum choose --header "$header" "$@" </dev/tty; return; fi
  local i=1 it ans
  printf '\n  %s%s%s\n' "$C_BOLD" "$header" "$C_RESET" >/dev/tty
  for it in "$@"; do printf '   %2d) %s\n' "$i" "$it" >/dev/tty; i=$((i + 1)); done
  read -r -p "  Number [1]: " ans </dev/tty
  ans=${ans:-1}
  eval "printf '%s\n' \"\${$ans}\""
}

# lines_to_array <varname> <<< "$lines"  (bash 3.2 has no mapfile)
lines_to_array() {
  local __name=$1 __line
  eval "$__name=()"
  while IFS= read -r __line; do
    [ -n "$__line" ] && eval "$__name+=(\"\$__line\")"
  done
}

banner() {
  printf '%s%s' "$C_BOLD" "$C_MAGENTA"
  cat <<'EOF'

   ____              _   __  __       __  __
  | __ )  ___   ___ | |_|  \/  |_   _|  \/  | __ _  ___
  |  _ \ / _ \ / _ \| __| |\/| | | | | |\/| |/ _` |/ __|
  | |_) | (_) | (_) | |_| |  | | |_| | |  | | (_| | (__
  |____/ \___/ \___/ \__|_|  |_|\__, |_|  |_|\__,_|\___|
                                |___/
EOF
  printf '%s\n' "$C_RESET"
}

print_summary() {
  local x
  printf '\n%s%s════════════════════════ SUMMARY ════════════════════════%s\n' "$C_BOLD" "$C_MAGENTA" "$C_RESET"
  if [ ${#SUMMARY_OK[@]} -gt 0 ]; then
    printf '\n%s✔ Done (%d)%s\n' "$C_GREEN$C_BOLD" ${#SUMMARY_OK[@]} "$C_RESET"
    for x in "${SUMMARY_OK[@]}"; do printf '   • %s\n' "$x"; done
  fi
  if [ ${#SUMMARY_SKIP[@]} -gt 0 ]; then
    printf '\n%s⤼ Skipped (%d)%s\n' "$C_DIM$C_BOLD" ${#SUMMARY_SKIP[@]} "$C_RESET"
    for x in "${SUMMARY_SKIP[@]}"; do printf '   • %s\n' "$x"; done
  fi
  if [ ${#SUMMARY_MANUAL[@]} -gt 0 ]; then
    printf '\n%s✋ Do these manually (%d)%s\n' "$C_YELLOW$C_BOLD" ${#SUMMARY_MANUAL[@]} "$C_RESET"
    for x in "${SUMMARY_MANUAL[@]}"; do printf '   • %s\n' "$x"; done
  fi
  if [ ${#SUMMARY_FAIL[@]} -gt 0 ]; then
    printf '\n%s✘ Failed (%d)%s — details in %s\n' "$C_RED$C_BOLD" ${#SUMMARY_FAIL[@]} "$C_RESET" "$LOG_FILE"
    for x in "${SUMMARY_FAIL[@]}"; do printf '   • %s\n' "$x"; done
    printf '   %sRe-run the script anytime; finished steps are skipped automatically.%s\n' "$C_DIM" "$C_RESET"
  fi
  printf '\n%sFull log: %s%s\n\n' "$C_DIM" "$LOG_FILE" "$C_RESET"
}
