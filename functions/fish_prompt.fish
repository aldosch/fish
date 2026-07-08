function fish_prompt
    # Re-detect palette so prompt reflects mode changes mid-session
    _aldo_dracula_apply_palette

    if test -n "$SSH_TTY"
        echo -n (set_color $p_red)"$USER"(set_color $p_fg)'@'(set_color $p_orange)(prompt_hostname)' '
    end

    echo -n (set_color $p_purple)(prompt_pwd)' '

    set_color -o
    if fish_is_root_user
        echo -n (set_color $p_red)'# '
    end
    echo -n (set_color $p_purple)'❯'(set_color $p_pink)'❯'(set_color $p_cyan)'❯ '
    set_color normal
end
