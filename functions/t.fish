# Usage:
#   t            -> attach/create session named by current dir (with short hash)
#   t foo        -> attach/create session "foo"
#   tl           -> list sessions (clean names)
#   tn foo       -> new named session (detached)
#   tk foo       -> kill session
#   tw name      -> new window (current session)
#   ts           -> choose-tree for sessions/windows

function __t_name_from_pwd
    set base (basename "$PWD")
    set short (printf "%s" "$PWD" | shasum -a 256 | cut -c1-4)
    echo "$base $short"
end

function t --description "Attach or create tmux session"
    set name (count $argv) > /dev/null; and set s $argv[1]; or set s (__t_name_from_pwd)
    tmux attach -t "$s" 2>/dev/null; or tmux new -s "$s"
    functions -e __t_name_from_pwd
end

function tl --description "List tmux sessions (clean)"
    tmux list-sessions -F '#{s/ [a-f0-9][a-f0-9][a-f0-9][a-f0-9]$//:session_name}' 2>/dev/null; or echo "no sessions"
end

function tn --description "Create new named session (detached)"
    test (count $argv) -ge 1; or begin; echo "usage: tn <name>"; return 1; end
    tmux new -d -s "$argv[1]"
end

function tk --description "Kill session"
    test (count $argv) -ge 1; or begin; echo "usage: tk <name>"; return 1; end
    tmux kill-session -t "$argv[1]"
end

function tw --description "New window in current session"
    set name (count $argv) > /dev/null; and set w "$argv[1]"; or set w ""
    tmux new-window -n "$w"
end

function ts --description "Interactive tree chooser"
    tmux choose-tree
end

