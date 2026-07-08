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
        set -g p_fg        "#282a36"
        set -g p_muted     "#6272a4"   # same — readable on both

        set -g p_purple    "#8b35d6"
        set -g p_pink      "#b5179e"
        set -g p_cyan      "#0096a0"
        set -g p_green     "#2d9648"
        set -g p_orange    "#c96a00"
        set -g p_red       "#c0392b"
        set -g p_yellow    "#b8860b"

        # slightly brighter variants (file names, secondary emphasis)
        set -g p_purple2   "#a040e8"
        set -g p_pink2     "#cc2eb5"
        set -g p_cyan2     "#00b4c0"
        set -g p_green2    "#3aad5a"
        set -g p_orange2   "#e07800"
        set -g p_red2      "#e05252"
        set -g p_yellow2   "#d4a017"
    end
end

# Apply on shell start
_aldo_dracula_apply_palette
