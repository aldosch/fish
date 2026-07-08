function watch-unzip --description "Watches a directory for new .zip files, unzips them, and optionally deletes the original."
    argparse d/delete -- $argv
    if set -q _flag_error
        return 1
    end

    if test (count $argv) -eq 0
        echo "Dude, you forgot the directory to watch!" >&2
        echo "Usage: watch-unzip [--delete] <directory>" >&2
        return 1
    end

    set watch_dir $argv[1]

    if not test -d "$watch_dir"
        echo "Directory not found: $watch_dir" >&2
        return 1
    end

    if not type -q fswatch
        echo "You need fswatch. Install it: brew install fswatch" >&2
        return 1
    end

    echo "👀 Watching for new .zip files in: $watch_dir"
    if set -q _flag_delete
        echo "🔥 --delete flag is active. Original .zip files will be deleted after extraction."
    end

    # The fix is here: --latency 1 tells fswatch to wait 1 second for more changes
    # before firing, effectively debouncing the events from Chrome.
    fswatch --latency 1 --event Created --event Renamed --include '\.zip$' --exclude '.*' "$watch_dir" | while read -l new_file
        # Wait until the file is no longer locked by another process (like Chrome)
        while lsof "$new_file" >/dev/null
            echo "⏳ File '$new_file' is in use, waiting for it to be released..."
            sleep 1
        end

        echo "✅ File is free, proceeding with unzip."
        if test -f "$new_file"
            echo "✅ Detected new zip file: $new_file"
            set dest_dir (basename "$new_file" .zip)

            if test -e "$watch_dir/$dest_dir"
                set dest_dir "$dest_dir-"(date +%s)
            end

            set dest_path "$watch_dir/$dest_dir"
            echo "📂 Creating directory and unzipping into: $dest_path"
            mkdir -p "$dest_path"
            unzip -q "$new_file" -d "$dest_path"

            if test $status -eq 0
                echo "👍 Successfully unzipped."
                if set -q _flag_delete
                    echo "🗑️  Deleting original file: $new_file"
                    rm "$new_file"
                end
            else
                echo "❌ Bummer. Failed to unzip $new_file"
            end

            echo ----------------------------------------
        end
    end
end
