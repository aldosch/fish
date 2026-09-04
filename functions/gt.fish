function gt --description 'Switch Ghostty tabs with fzf (cwd + last command per tab)'
    # The tab bar is hidden by the local ghostty patch (~/repos/ghostty,
    # branch aldo/patches); gt is the visual switcher.
    #
    # Enumerates tabs via the Ghostty 1.3 AppleScript API (window index, stable
    # tab id, selected flag, focused terminal cwd + tty), joins the tty with the
    # last-command registry written by fish/conf.d/ghostty-session.fish, then
    # fzf over rows and `select tab id` on accept.
    #
    # Fields per result line: winIndex \t tabId \t selected \t cwd \t tty
    # Display shows only cwd + last command (--with-nth); the hidden fields
    # carry the selection target.

    set -l script '
        tell application "Ghostty"
            set out to ""
            set wi to 0
            repeat with w in windows
                set wi to wi + 1
                repeat with t in tabs of w
                    set tid to id of t
                    set tsel to selected of t
                    set tcwd to ""
                    set ttty to ""
                    try
                        set ft to focused terminal of t
                        set tcwd to working directory of ft
                        set ttty to tty of ft
                    end try
                    set out to out & wi & "\\t" & tid & "\\t" & tsel & "\\t" & tcwd & "\\t" & ttty & linefeed
                end repeat
            end repeat
            return out
        end tell'

    set -l raw (osascript -e $script 2>/dev/null)
    if test -z "$raw"
        echo "gt: no tabs found (is Ghostty running?)"
        return 1
    end

    set -l rows
    for line in (string split \n -- $raw)
        set -l f (string split \t -- $line)
        test (count $f) -lt 5; and continue

        set -l cwd $f[4]
        if test -z "$cwd"
            set cwd "(cwd pending)"
        else
            set cwd (string replace -- "$HOME" "~" $cwd)
        end

        set -l last ""
        set -l ttyname (basename $f[5] 2>/dev/null)
        if test -n "$ttyname" -a -f "$__ghostty_cmddir/$ttyname"
            set last (head -n1 "$__ghostty_cmddir/$ttyname" 2>/dev/null)
        end

        set -l marker ""
        test "$f[3]" = "true"; and set marker "* "

        set -a rows "$f[1]\t$f[2]\t$marker$cwd\t$last"
    end

    if not set -q rows[1]
        echo "gt: no tabs found"
        return 1
    end

    set -l choice (printf '%s\n' $rows | fzf \
        --height=40% --reverse \
        --prompt='tab> ' \
        --delimiter='\t' --with-nth=3,4 \
        --header='cwd  last command  (* = current tab)')
    test -n "$choice"; or return 0

    set -l f (string split \t -- $choice)
    osascript -e "tell application \"Ghostty\" to select tab id \"$f[2]\" of window $f[1]" >/dev/null
end
