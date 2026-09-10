# aldo-dracula-palette.fish
# Shared adaptive color palette for all fish functions, prompt, and syntax
# highlighting. Sets global variables based on macOS dark/light mode.
# Sourced automatically by fish via conf.d on every shell start.
#
# The values are ANSI palette SLOT NUMBERS (0-15), not hex. This is the
# theme-switch fix: cells drawn with palette indices are re-resolved by
# Ghostty against the active theme's palette on every repaint, so when
# macOS appearance flips (theme = dark:aldo-dracula,light:aldo-dracula-light)
# existing text instantly re-renders in the new theme's colors. Hex/truecolor
# values are baked into the grid per-cell and go stale on a theme toggle
# (dark ink stranded on a dark background).
#
# The two ghostty theme files (ghostty/themes/aldo-dracula*) are the source
# of truth for what each slot looks like in each mode. They carry the same
# Dracula / Alucard hues as nvim (lua/aldo-dracula*.lua) and opencode
# (opencode/themes/aldo-dracula.json), so everything matches.
#
# SEMANTIC MAP (use these roles, never raw numbers, in new functions):
#   p_fg      body text, task/step names
#   p_muted   secondary text: timings, hints, paths, detail lines
#   p_purple  headers, banners, borders, spinners, interactive selection
#   p_cyan    commands, actions, section headers
#   p_green   success (✓), added
#   p_red     errors (✗), failures
#   p_orange  warnings (▲ ⚠ ▸ extra/modified)
#   p_yellow  pending/missing items, attention-lite
#   p_pink    prompt accents, deleted files
#   p_*2      bright variants: list items, secondary emphasis
#   p_bg/p_panel/p_element   fzf gutters, borders, chrome
#
# SLOT MAP (what each role resolves to in ghostty/themes/aldo-dracula*):
#    1 red      2 green     3 yellow    4 blue (purple)
#    5 magenta  6 cyan      8 brblack (muted)  9 brred 10 brgreen
#   11 bryellow 12 brblue (purple2) 13 brmagenta 14 brcyan
#
# RULES:
#   - Never stack gum's --faint on top of a $p_* color: it double-dims and
#     washes out on light backgrounds. Color alone carries the hierarchy.
#   - Reference $p_* variables directly; call _aldo_dracula_apply_palette at
#     the top of a function if it needs the fzf/pager chrome hexes fresh.
#   - Force a mode for testing/SSH: ALDO_THEME=light|dark.
#   - gum/termenv does not understand color names: pass slot numbers or hex.
#     fish accepts the same numbers (set_color 8 -> 38;5;8 -> ghostty slot 8).
#   - Orange has no palette slot, so p_orange/p_orange2 fold into the yellow
#     slots (3/11): same urgency family, and they follow the theme like
#     everything else instead of stranding truecolor ink on theme toggles.

function _aldo_terminal_bg
    # Ask the terminal for its actual background color (OSC 11 query).
    # This is the ground truth: it reflects the real background text is
    # drawn on, even when the window theme and macOS appearance disagree
    # (mid-toggle, forced theme). Works over SSH too, since the local
    # terminal answers through the tty. Prints "dark" or "light"; prints
    # nothing and returns 1 when the terminal can't be asked.
    # Interactive shells only: `fish -c` subshells (nixx DAG tasks, etc.)
    # skip straight to the macOS fallback. NB: can't use `test -t 1` here,
    # the function's own stdout is a pipe when called via command
    # substitution.
    status is-interactive; or return 1
    # Ghostty only: it answers the query instantly. Other terminals are
    # not worth the (bounded) wait; TERM=xterm-ghostty survives SSH.
    if not string match -qi '*ghostty*' -- "$TERM_PROGRAM" "$TERM"
        return 1
    end
    # After two silent terminals (e.g. tmux/screen without passthrough)
    # stop querying for this session and use the macOS fallback.
    if not set -q _aldo_bg_failures
        set -g _aldo_bg_failures 0
    end
    if test $_aldo_bg_failures -ge 2
        return 1
    end

    set -l saved (stty -f /dev/tty -g 2>/dev/null)
    if test -z "$saved"
        set -g _aldo_bg_failures (math $_aldo_bg_failures + 1)
        return 1
    end
    # raw + MIN 0 TIME 2: read returns as soon as the response arrives,
    # at worst 0.2s of silence
    stty -f /dev/tty raw -echo min 0 time 2 2>/dev/null
    printf '\033]11;?\033\\' > /dev/tty
    set -l resp (dd bs=64 count=1 < /dev/tty 2>/dev/null)
    stty -f /dev/tty $saved 2>/dev/null

    # response: ESC]11;rgba:rrrr/gggg/bbbb/aaaaESC\ (hex components, 16-bit
    # in ghostty; tolerate narrower widths by scaling the threshold)
    set -l m (string match -r 'rgba?:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+)' -- $resp)
    if test (count $m) -lt 4
        set -g _aldo_bg_failures (math $_aldo_bg_failures + 1)
        return 1
    end
    set -g _aldo_bg_failures 0
    set -l half (math "2 ^ (" (string length -- $m[2]) " * 4) / 2")
    set -l lum (math "0.2126 * 0x$m[2] + 0.7152 * 0x$m[3] + 0.0722 * 0x$m[4]")
    if test "$lum" -gt "$half"
        echo light
    else
        echo dark
    end
end

function _aldo_dracula_apply_palette
    # Mode resolution order: explicit argument > ALDO_THEME env var
    # (exported; useful for SSH and child shells) > terminal background
    # (OSC 11, the ground truth) > macOS appearance.
    #
    # Mode only matters for the fzf/pager chrome hexes (p_bg/p_panel/
    # p_element): the text roles below are slot numbers, so they follow the
    # ghostty theme automatically on every repaint.
    set -l _mode
    if set -q argv[1]; and test -n "$argv[1]"
        set _mode (string lower -- $argv[1])
    else if set -q ALDO_THEME[1]; and test -n "$ALDO_THEME"
        set _mode (string lower -- $ALDO_THEME)
    else
        set _mode (_aldo_terminal_bg)
        if not set -q _mode[1]
            set _mode (defaults read -g AppleInterfaceStyle 2>/dev/null | string lower)
        end
    end
    if test "$_mode" = dark
        # ── Dark (Dracula) chrome ─────────────────────────────
        set -g p_bg        "#161616"
        set -g p_panel     "#21222c"
        set -g p_element   "#282a36"
    else
        # ── Light (Alucard) chrome ────────────────────────────
        set -g p_bg        "#ffffff"
        set -g p_panel     "#f0f0f5"
        set -g p_element   "#e4e4ef"
    end

    # ── Text roles: ANSI palette slots (see SLOT MAP above) ──
    # Slot numbers re-resolve through the active ghostty theme palette on
    # every repaint, so existing sessions heal instantly on a macOS theme
    # toggle. p_fg = default foreground; gum renders it as default fg too
    # (termenv ignores values it can't parse, which is the desired no-op).
    set -g p_fg        normal
    set -g p_muted     8    # brblack — comment blue-grey #6272a4

    set -g p_purple    4    # blue slot — dracula purple
    set -g p_pink      5    # magenta slot
    set -g p_cyan      6    # cyan slot
    set -g p_green     2    # green slot
    set -g p_red       1    # red slot
    set -g p_orange    3    # folded into yellow (no orange slot)
    set -g p_yellow    3    # yellow slot

    # bright variants (file names, secondary emphasis)
    set -g p_purple2   12   # brblue
    set -g p_pink2     13   # brmagenta
    set -g p_cyan2     14   # brcyan
    set -g p_green2    10   # brgreen
    set -g p_orange2   11   # folded into bryellow
    set -g p_red2      9    # brred
    set -g p_yellow2   11   # bryellow

    # ── Fish syntax highlighting + pager ─────────────────────
    # Kept in the palette so typed commands, autosuggestions, and completion
    # UI follow the terminal theme like everything else. Same role→slot
    # mapping in both modes.
    set -g fish_color_normal        normal
    set -g fish_color_command       $p_fg
    set -g fish_color_param         $p_cyan
    set -g fish_color_quote         $p_yellow
    set -g fish_color_redirection   $p_cyan --bold
    set -g fish_color_operator      $p_cyan2
    set -g fish_color_escape        $p_cyan2
    set -g fish_color_end           $p_green
    set -g fish_color_comment       $p_muted
    set -g fish_color_error         $p_red
    set -g fish_color_status        $p_red
    set -g fish_color_autosuggestion $p_muted
    set -g fish_color_valid_path    --underline
    set -g fish_color_cancel        -r
    set -g fish_color_history_current --bold
    set -g fish_color_host          $p_fg
    set -g fish_color_host_remote   $p_yellow
    set -g fish_color_user          $p_green2
    set -g fish_color_cwd           $p_green
    set -g fish_color_cwd_root      $p_red
    set -g fish_color_search_match  normal --background=$p_muted
    set -g fish_color_selection     normal --bold --background=$p_muted
    set -g fish_pager_color_completion        $p_fg
    set -g fish_pager_color_description       $p_yellow
    set -g fish_pager_color_prefix            $p_fg --bold --underline
    set -g fish_pager_color_progress          $p_element --background=$p_cyan
    set -g fish_pager_color_selected_background --background=$p_element
end

# Apply on shell start
_aldo_dracula_apply_palette
