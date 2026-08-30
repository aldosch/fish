# dotfiles-motd.fish - subtle MOTD on shell launch
#
# Sourced by fish on every shell start (conf.d). If the background health
# check (dotfiles-health) has written notices to ~/.local/state/dotfiles/notices.json,
# print one muted line pointing to `dotfix`. Shows every session until the
# notices are resolved (via `dotfix`) or snoozed (via `dot dismiss`).
#
# Design goals:
#   - Silent when there's nothing to action (preserves the empty-greeting status quo)
#   - Shows every new session until resolved or dismissed
#   - One line, subtle colors, never blocks or prompts
#   - Instant — reads a small JSON file, no network, no subprocesses beyond gum

# Only show in interactive shells
if not status --is-interactive
    return
end

set -l _dot_notices ~/.local/state/dotfiles/notices.json

# No state file yet (fresh machine, health check hasn't run) -> silent
test -f "$_dot_notices"; or return

# Read count, message, and last_shown in one jq pass
set -l _dot_data (jq -r '"\(.count // 0)|\(.message // "")|\(.last_shown // "")"' "$_dot_notices" 2>/dev/null)
test $status -eq 0; or return

set -l _dot_parts (string split "|" -- $_dot_data)
set -l _dot_count $_dot_parts[1]
set -l _dot_msg $_dot_parts[2]
set -l _dot_last_shown $_dot_parts[3]

# No notices -> silent (preserves empty greeting)
test "$_dot_count" -gt 0 2>/dev/null; or return

# Dismissed today (via `dot dismiss`) -> silent
set -l _dot_today (date +%Y-%m-%d)
test "$_dot_last_shown" = "$_dot_today"; and return

# Print one subtle line. Colors from the dracula palette (available since
# conf.d/aldo-dracula-palette.fish is sourced before this file alphabetically).
# If the message is empty (shouldn't happen when count > 0, but guard anyway),
# use a generic fallback.
test -n "$_dot_msg"; or set _dot_msg "some stuff needs attention"

# Use native set_color instead of gum: the gum pipeline (join + 3 styles)
# forks 4 processes (~155ms measured) on EVERY shell that shows this line,
# which doubles total startup. set_color renders identical output with zero
# forks. Colors come from the dracula palette (available since
# conf.d/aldo-dracula-palette.fish is sourced before this file alphabetically).
printf '%s%s%s%s%s%s%s%s\n' \
    (set_color $p_muted)"  · "(set_color normal) \
    $_dot_msg \
    (set_color $p_muted)"  →  "(set_color normal) \
    (set_color $p_cyan --bold)dotfix(set_color normal)
