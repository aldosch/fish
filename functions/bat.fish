function bat --wraps bat --description "bat with auto dark/light theme"
    set -l _theme GitHub
    if is-dark
        set _theme Dracula
    end
    BAT_THEME=$_theme command bat $argv
end
