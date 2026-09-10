# set_color - passthrough wrapper that accepts ANSI palette slot numbers.
#
# The shared palette (conf.d/aldo-dracula-palette.fish) stores text roles as
# slot numbers 0-15 so gum and fish_color_* can both follow the active
# Ghostty theme. fish's builtin set_color rejects numbers ("Unknown color
# '8'"), so this wrapper translates 0-15 to the equivalent named color and
# delegates. Hex and named colors pass through untouched.
#
# Slots resolve through the terminal's active 16-color palette, so text
# re-renders in the new theme's colors when macOS appearance toggles.
function set_color --description 'set_color with ANSI slot number support (0-15 -> named colors)'
    set -l argv_out
    for arg in $argv
        switch $arg
            case 0
                set arg black
            case 1
                set arg red
            case 2
                set arg green
            case 3
                set arg yellow
            case 4
                set arg blue
            case 5
                set arg magenta
            case 6
                set arg cyan
            case 7
                set arg white
            case 8
                set arg brblack
            case 9
                set arg brred
            case 10
                set arg brgreen
            case 11
                set arg bryellow
            case 12
                set arg brblue
            case 13
                set arg brmagenta
            case 14
                set arg brcyan
            case 15
                set arg brwhite
        end
        set -a argv_out $arg
    end
    builtin set_color $argv_out
end
