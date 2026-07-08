function bat --wraps bat --description "bat with auto dark/light theme"
    set -l _theme
    set -l _style (defaults read -g AppleInterfaceStyle 2>/dev/null)
    if test "$_style" = Dark
        set _theme Dracula
    else
        set _theme GitHub
    end
    BAT_THEME=$_theme command bat $argv
end
