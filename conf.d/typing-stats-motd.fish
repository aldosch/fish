# typing-stats-motd.fish - subtle MOTD line for Typing Stats CPU findings
#
# Sourced by fish on every interactive shell start (conf.d). If the background
# monitor (com.aldo.typing-stats-monitor) has written analysis findings to
# ~/.local/state/typing-stats/findings.json, print one muted line pointing at
# `tstats` (which resumes the analysis session in the opencode TUI).
#
# Behavior:
#   - action_needed: shows every session until dismissed (`tstats dismiss`)
#     or cleared (`tstats reset`)
#   - benign: informational — shows once, stamps last_shown, goes quiet
#   - error: shows like action_needed (analysis failed, needs a re-run)
#   - silent when no findings, or already shown/dismissed today
#
# Design mirrors conf.d/dotfiles-motd.fish:
#   - Silent when there's nothing to action (preserves empty greeting)
#   - One line, subtle colors, never blocks or prompts
#   - Instant — reads a small JSON file, no subprocesses beyond gum/jq

# Only show in interactive shells
if not status --is-interactive
    return
end

set -l _ts_findings ~/.local/state/typing-stats/findings.json

# No findings yet (monitor hasn't analyzed) -> silent
test -f "$_ts_findings"; or return

# Read verdict, headline, and last_shown in one jq pass
set -l _ts_data (jq -r '"\(.verdict // "unknown")|\(.headline // "")|\(.last_shown // "")"' "$_ts_findings" 2>/dev/null)
test $status -eq 0; or return

set -l _ts_parts (string split "|" -- $_ts_data)
set -l _ts_verdict $_ts_parts[1]
set -l _ts_msg $_ts_parts[2]
set -l _ts_last_shown $_ts_parts[3]

# Already shown/dismissed today -> silent
set -l _ts_today (date +%Y-%m-%d)
test "$_ts_last_shown" = "$_ts_today"; and return

# Guard against an empty headline (shouldn't happen, but stay subtle anyway)
test -n "$_ts_msg"; or set _ts_msg "typing stats has analysis findings"

# Color by verdict: action_needed/error get yellow, benign stays foreground
set -l _ts_color $p_fg
if test "$_ts_verdict" = action_needed -o "$_ts_verdict" = error
    set _ts_color $p_yellow
end

# benign is informational: show once, then auto-snooze by stamping last_shown
if test "$_ts_verdict" = benign
    jq --arg today "$_ts_today" '.last_shown = $today' "$_ts_findings" >"$_ts_findings.tmp" 2>/dev/null
    and mv "$_ts_findings.tmp" "$_ts_findings"
end

gum join --horizontal \
    (gum style --foreground $p_muted "  · ") \
    (gum style --foreground $_ts_color "$_ts_msg") \
    (gum style --foreground $p_muted "  →  ") \
    (gum style --foreground $p_cyan --bold "tstats")
