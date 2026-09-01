function norm-log --description "Check norm-shots processing log"
    argparse f/follow -- $argv
    if set -q _flag_error
        return 1
    end

    set -l log_file "$HOME/Library/Logs/norm-shots.log"

    if not test -f "$log_file"
        echo "no log yet: $log_file"
        return 1
    end

    if set -q _flag_follow
        tail -f "$log_file"
    else
        tail -n 20 "$log_file"
    end
end
