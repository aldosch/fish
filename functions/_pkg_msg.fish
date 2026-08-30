function _pkg_msg --description 'Shared output helper for package-manager wrappers (gum + plain fallback)'
    set -l kind $argv[1]
    set -l text $argv[2..-1]
    set -l symbol "  ·"
    set -l color $p_muted
    switch $kind
        case ok
            set symbol "  ✓"
            set color $p_green
        case warn
            set symbol "  ▸"
            set color $p_orange
        case info
            set symbol "  →"
            set color $p_cyan
    end
    if type -q gum
        gum join --horizontal \
            (gum style --foreground $color "$symbol") \
            (gum style --foreground $p_fg " $text")
    else
        echo "$symbol $text"
    end
end
