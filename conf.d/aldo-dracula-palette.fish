# aldo-dracula-palette.fish
# Shared adaptive color palette for all fish functions, prompt, and syntax
# highlighting. Sets global variables based on macOS dark/light mode.
# Sourced automatically by fish via conf.d on every shell start.
#
# The values are the same Dracula / Alucard hues used by the other theme
# surfaces, so everything matches: nvim (lua/aldo-dracula*.lua), opencode
# (opencode/themes/aldo-dracula.json), ghostty (ghostty/themes/aldo-dracula*).
#
# SEMANTIC MAP (use these roles, never raw colors, in new functions):
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
# RULES:
#   - Never stack gum's --faint on top of a $p_* color: it double-dims and
#     washes out on light backgrounds. Color alone carries the hierarchy.
#   - Reference $p_* variables directly; call _aldo_dracula_apply_palette at
#     the top of a function to re-detect after a macOS appearance switch.
#   - Force a mode for testing/SSH: ALDO_THEME=light|dark.

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
        # ── Dark (Dracula) ────────────────────────────────────
        set -g p_bg        "#161616"
        set -g p_panel     "#21222c"
        set -g p_element   "#282a36"
        set -g p_fg        "#f8f8f2"
        set -g p_muted     "#6272a4"   # comment blue-grey

        set -g p_purple    "#bd93f9"
        set -g p_pink      "#ff79c6"
        set -g p_cyan      "#8be9fd"
        set -g p_green     "#50fa7b"
        set -g p_orange    "#ffb86c"
        set -g p_red       "#ff5555"
        set -g p_yellow    "#f1fa8c"

        # bright variants (file names, secondary emphasis)
        set -g p_purple2   "#d6acff"
        set -g p_pink2     "#ff92df"
        set -g p_cyan2     "#a4ffff"
        set -g p_green2    "#69ff94"
        set -g p_orange2   "#ffc896"
        set -g p_red2      "#ff6e6e"
        set -g p_yellow2   "#ffffa5"
    else
        # ── Light (Alucard) ───────────────────────────────────
        # Values shared with nvim + opencode + ghostty light themes.
        # Text roles keep AA contrast on white; *2 variants are the
        # nvim bright_* accents for list items and secondary emphasis.
        set -g p_bg        "#ffffff"
        set -g p_panel     "#f0f0f5"
        set -g p_element   "#e4e4ef"
        set -g p_fg        "#282a36"
        set -g p_muted     "#6272a4"   # canonical Dracula comment hue

        set -g p_purple    "#6b21c2"   # deep violet — headers, borders
        set -g p_pink      "#b5179e"   # magenta
        set -g p_cyan      "#0085a1"   # teal — section headers
        set -g p_green     "#2d9648"   # green — checkmarks
        set -g p_orange    "#b06d00"   # amber, darkened for text legibility
        set -g p_red       "#c0392b"   # red
        set -g p_yellow    "#8a6900"   # goldenrod, darkened for text legibility

        # bright variants (nvim bright_* values; list items, secondary emphasis)
        set -g p_purple2   "#8b35d6"
        set -g p_pink2     "#cc2eb5"
        set -g p_cyan2     "#00a0c0"
        set -g p_green2    "#3aad5a"
        set -g p_orange2   "#d4820a"
        set -g p_red2      "#e05252"
        set -g p_yellow2   "#d4a017"
    end

    # ── Fish syntax highlighting + pager ─────────────────────
    # Kept in the palette so typed commands, autosuggestions, and completion
    # UI adapt to dark/light mode like everything else. Replaces the
    # fish-4.3-migrated fish_frozen_theme.fish (fixed ANSI names, not
    # adaptive). Same role→slot mapping in both modes, so dark renders
    # exactly as before via the terminal's Dracula-mapped palette.
    set -g fish_color_normal        $p_fg
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
    set -g fish_color_search_match  $p_fg --background=$p_muted
    set -g fish_color_selection     $p_fg --bold --background=$p_muted
    set -g fish_pager_color_completion        $p_fg
    set -g fish_pager_color_description       $p_yellow
    set -g fish_pager_color_prefix            $p_fg --bold --underline
    set -g fish_pager_color_progress          $p_element --background=$p_cyan
    set -g fish_pager_color_selected_background --background=$p_element
end

# Apply on shell start
_aldo_dracula_apply_palette
