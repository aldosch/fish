# dotfiles-motd.fish - subtle MOTD for dotfiles drift
#
# Sourced by fish on every shell start (conf.d). Scoped to ~/.config
# sessions: shells that start there (or cd into it, once per session) print
# one muted line pointing to `dotfix` when the background health check has
# written notices to ~/.local/state/dotfiles/notices.json. Everywhere else
# fish stays silent.
#
# The health check itself runs daily via the `maintenance` LaunchAgent
# (plus `dot refresh` on demand). As a freshness backstop for this display,
# a shell starting in ~/.config kicks a background refresh when the notices
# are older than 4h.
#
# Design goals:
#   - Silent everywhere except ~/.config (preserves the empty-greeting status quo)
#   - Shows every session in ~/.config until the notices are resolved
#     (via `dotfix`) or snoozed (via `dot dismiss`)
#   - One line, flush left and tight above the prompt, subtle colors,
#     never blocks or prompts
#   - Instant — reads a small JSON file, no network, no blocking subprocesses

# Print the one-line notice if there's something to action. Returns 0 if the
# line was printed. Guards: file exists, valid JSON, count > 0, not
# dismissed today (via `dot dismiss`).
function __dot_motd_show
    set -l notices_file "$argv[1]"
    test -f "$notices_file"; or return 1

    # Read count, message, and last_shown in one jq pass
    set -l data (jq -r '"\(.count // 0)|\(.message // "")|\(.last_shown // "")"' "$notices_file" 2>/dev/null)
    test $status -eq 0; or return 1

    set -l parts (string split "|" -- $data)
    set -l count $parts[1]
    set -l msg $parts[2]
    set -l last_shown $parts[3]

    # No notices -> silent (preserves empty greeting)
    test "$count" -gt 0 2>/dev/null; or return 1

    # Dismissed today (via `dot dismiss`) -> silent
    set -l today (date +%Y-%m-%d)
    test "$last_shown" = "$today"; and return 1

    # Fallback if the message is empty (shouldn't happen when count > 0)
    test -n "$msg"; or set msg "some stuff needs attention"

    # Mark this session as shown (also silences the cd-in hook below)
    set -g __dot_motd_shown 1

    # Use native set_color instead of gum: the gum pipeline (join + 3 styles)
    # forks 4 processes (~155ms measured) on EVERY shell that shows this line,
    # which doubles total startup. set_color renders identical output with zero
    # forks. Colors come from the dracula palette (available since
    # conf.d/aldo-dracula-palette.fish is sourced before this file
    # alphabetically). Flush left, tight: no leading indent, single space
    # around the arrow, and no bold on the action word (keeps the line
    # visually small).
    printf '%s%s%s%s\n' \
        $msg \
        (set_color $p_muted)" → "(set_color normal) \
        (set_color $p_cyan)dotfix(set_color normal)
    return 0
end

# Cd-in hook: same notice when a session lands in ~/.config later. Fires on
# every PWD change but exits on two string compares unless it applies, and
# shows at most once per session (via __dot_motd_shown).
function __dot_motd_on_pwd --on-variable PWD
    status --is-interactive; or return
    set -q __dot_motd_shown; and return
    test "$PWD" = "$HOME/.config"; or return
    __dot_motd_show ~/.local/state/dotfiles/notices.json
end

# Startup path — interactive shells in ~/.config only
if status --is-interactive
    and test "$PWD" = "$HOME/.config"
    set -l notices_file ~/.local/state/dotfiles/notices.json

    # Show the current state first (instant), then keep the data fresh:
    # kick the health check in the background when the notices are older
    # than 4h, so the next session isn't looking at stale state. The daily
    # maintenance run covers the machine-wide schedule either way.
    __dot_motd_show $notices_file

    if not test -f "$notices_file"
        or test (path mtime --relative "$notices_file") -gt 14400
        fish -c dotfiles-health >/dev/null 2>&1 &
        disown $last_pid
    end
end
