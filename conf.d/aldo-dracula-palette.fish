# aldo-dracula-palette.fish
# Shared adaptive color palette for all fish functions and prompt.
# Sets global variables based on macOS dark/light mode.
# Sourced automatically by fish via conf.d on every shell start.
#
# Usage in functions: just reference $p_* variables directly.
# Re-detect at runtime: call _aldo_dracula_apply_palette

function _aldo_dracula_apply_palette
    set -l _mode (defaults read -g AppleInterfaceStyle 2>/dev/null)
    if test "$_mode" = Dark
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
        set -g p_bg        "#ffffff"
        set -g p_panel     "#f0f0f5"
        set -g p_element   "#e4e4ef"
        set -g p_fg        "#1a1b26"
        set -g p_muted     "#4a5694"   # darker than dark-mode muted; ~4.7:1 on white

        set -g p_purple    "#6b1fa8"   # deeper violet — visible borders & accents
        set -g p_pink      "#961480"   # deeper magenta
        set -g p_cyan      "#006f7a"   # deep teal — section headers
        set -g p_green     "#1a7530"   # deep green — checkmarks
        set -g p_orange    "#a85500"   # dark amber — warnings
        set -g p_red       "#a81a10"   # deep red — errors
        set -g p_yellow    "#7a5800"   # dark gold — missing items

        # slightly lighter variants (file names, secondary emphasis)
        set -g p_purple2   "#8b2ec8"
        set -g p_pink2     "#b01898"
        set -g p_cyan2     "#008a96"
        set -g p_green2    "#228c3a"
        set -g p_orange2   "#c46200"
        set -g p_red2      "#c42010"
        set -g p_yellow2   "#956b00"
    end
end

# Apply on shell start
_aldo_dracula_apply_palette
