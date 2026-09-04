# Per-session metadata for the gt tab switcher. Ghostty-only, interactive-only.
#
# - Emits OSC 7 on every PWD change so Ghostty's `working directory` (exposed
#   per-terminal via the 1.3 AppleScript API) stays current
# - Records the last executed command, keyed by tty basename, to
#   $__ghostty_cmddir — gt joins it with the AppleScript tty field

set -g __ghostty_cmddir ~/.cache/ghostty-cmds

if status is-interactive; and string match -qi 'ghostty*' -- "$TERM_PROGRAM" "$TERM"
    function __ghostty_session_on_pwd --on-variable PWD --description 'Emit OSC 7 cwd for Ghostty'
        printf '\e]7;file://%s%s\a' (hostname) "$PWD"
    end

    function __ghostty_session_on_postexec --on-event fish_postexec --description 'Record last command for gt'
        set -l cmd (string replace -a \t ' ' -- $argv[1] | string collect)
        test -n "$cmd"; or return 0
        mkdir -p $__ghostty_cmddir
        set -l ttyname (basename (tty) 2>/dev/null)
        test -n "$ttyname"; and printf '%s\n' $cmd >"$__ghostty_cmddir/$ttyname"
    end

    # Prune registry entries older than 90 days (ttys accumulate across reboots)
    function __ghostty_session_prune --on-event fish_prompt --description 'Prune stale gt command registry'
        set -l flag ~/.cache/ghostty-cmds/.pruned
        if not test -f $flag; or test (path mtime -R -- $flag 2>/dev/null) -gt 604800
            mkdir -p $__ghostty_cmddir
            find $__ghostty_cmddir -type f -mtime +90 -delete 2>/dev/null
            touch $flag
        end
    end
end
