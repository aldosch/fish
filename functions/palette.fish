# palette - preview the shared aldo color palette in the current mode
#
# Prints every semantic role as it renders on screen, so new functions can
# be checked against the system without flipping macOS appearance.
#
# Usage:
#   palette            render with the current macOS mode
#   palette light      render the light (Alucard) palette
#   palette dark       render the dark (Dracula) palette
#   palette light dark render both, back to back

function palette --description "Preview the shared aldo color palette (palette [light|dark])"
    for mode in $argv
        if not contains -- "$mode" light dark
            echo "usage: palette [light|dark]" >&2
            return 1
        end
    end

    if test (count $argv) -eq 0
        __palette_render
        return
    end

    for mode in $argv
        _aldo_dracula_apply_palette $mode
        __palette_render $mode
    end
    # restore palette for the current macOS mode
    _aldo_dracula_apply_palette
end

function __palette_render --argument-names mode_label
    if not set -q mode_label[1]
        set -l _m (defaults read -g AppleInterfaceStyle 2>/dev/null)
        set mode_label (test "$_m" = Dark; and echo dark; or echo light)
    end

    echo
    gum style --bold --foreground $p_purple --border rounded --border-foreground $p_purple \
        --padding "0 2" --align center \
        "palette · $mode_label" \
        (gum style --foreground $p_muted "shared by fish · ghostty · nvim · opencode")

    gum style --foreground $p_cyan --bold "⚙  sections"
    echo "  "(gum style --foreground $p_green "✓")" "(gum style --foreground $p_fg "nix")"  "(gum style --foreground $p_muted "(49s)")
    echo "  "(gum style --foreground $p_red "✗")" "(gum style --foreground $p_fg "skills")"  "(gum style --foreground $p_muted "(10m 2s)")"  "(gum style --foreground $p_muted "log: /tmp/nixx-dag-skills.log")
    echo "  "(gum style --foreground $p_muted "– pending section")
    echo "  "(gum style --foreground $p_purple "⠋")" "(gum style --foreground $p_fg "brew")" "(gum style --foreground $p_muted ": upgrading node · ==> Upgrading node")
    echo "    "(gum style --foreground $p_orange "▸ extra")" "(gum style --foreground $p_fg "some-pkg")" "(gum style --foreground $p_muted "brew cask")
    echo "    "(gum style --foreground $p_muted "    → resolve with: nixx check")
    echo

    echo "  "(gum style --bold --foreground $p_purple --border rounded --border-foreground $p_purple \
        "✓  Done · 10m 5s" \
        (gum style --foreground $p_muted "11 packages upgraded"))
    echo

    gum style --foreground $p_purple --bold "── semantic roles"
    echo "  "(gum style --foreground $p_green "■ success")"  "(gum style --foreground $p_red "■ error")"  "(gum style --foreground $p_orange "■ warning")"  "(gum style --foreground $p_yellow "■ pending")"  "(gum style --foreground $p_cyan "■ action")"  "(gum style --foreground $p_purple "■ heading")"  "(gum style --foreground $p_pink "■ prompt")
    echo "  "(gum style --foreground $p_fg "■ body")"  "(gum style --foreground $p_muted "■ secondary")"  "(gum style --foreground $p_purple2 "■ purple2")"  "(gum style --foreground $p_green2 "■ green2")"  "(gum style --foreground $p_orange2 "■ orange2")"  "(gum style --foreground $p_red2 "■ red2")"  "(gum style --foreground $p_cyan2 "■ cyan2")"  "(gum style --foreground $p_yellow2 "■ yellow2")
    echo
end
