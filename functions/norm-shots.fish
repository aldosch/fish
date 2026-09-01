function norm-shots --description "Auto-normalise audio on new video recordings in ~/shots"
    # Host gate: only run on book (MacBook)
    if test "$hostname" != book
        return 0
    end

    # launchd runs with a minimal PATH — set up what we need
    set -x PATH /run/current-system/sw/bin /opt/homebrew/bin /usr/bin /bin /usr/sbin /sbin

    set -l shots_dir "$HOME/shots"
    set -l state_dir "$HOME/.local/state/norm-shots"
    set -l log_file "$HOME/Library/Logs/norm-shots.log"
    mkdir -p "$state_dir" (dirname "$log_file")

    # Find all video files in ~/shots (non-recursive)
    set -l files (find "$shots_dir" -maxdepth 1 -type f \( -name '*.mp4' -o -name '*.mov' \) 2>/dev/null)
    if test (count $files) -eq 0
        return 0
    end

    for f in $files
        set -l base (basename "$f")
        set -l done_marker "$state_dir/$base.done"
        set -l proc_marker "$state_dir/$base.processing"

        # Skip if already done or currently being processed
        if test -f "$done_marker"; or test -f "$proc_marker"
            continue
        end

        # Wait for file to be fully written (up to 30s)
        set -l waited 0
        set -l ready true
        while lsof "$f" >/dev/null 2>&1
            if test $waited -ge 30
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] SKIP: $base still in use after 30s" >>"$log_file"
                set ready false
                break
            end
            sleep 1
            set waited (math $waited + 1)
        end

        if test "$ready" != true
            continue
        end

        # Create processing marker to prevent re-entry from WatchPaths events
        touch "$proc_marker"

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Processing: $base" >>"$log_file"

        # Normalise audio (reuses the fix-audio fish function)
        fix-audio "$f"
        if test $status -eq 0
            mv "$proc_marker" "$done_marker"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Done: $base" >>"$log_file"
        else
            rm -f "$proc_marker"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: fix-audio failed for $base" >>"$log_file"
        end
    end
end
