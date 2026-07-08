function pjson --description 'Format JSON files with jq'
    if not type -q gum
        echo "Error: gum is not installed. Install with 'brew install gum'"
        return 1
    end

    set -l files *.json
    if test -z "$files" -o ! -f "$files[1]"
        gum style --foreground 220 "⚠ No JSON files found in current directory"
        return 1
    end

    set -l total (count $files)
    set -l formatted
    set -l formatted_before
    set -l formatted_after
    set -l failed

    for file in $files
        set -l size (command du -h "$file" | cut -f1 | string trim)
        gum style --foreground 245 "  formatting $file ($size)..."

        set -l before (command stat -f%z "$file")

        if jq '.' "$file" > "$file.tmp" 2>/dev/null
            mv "$file.tmp" "$file"
            set -l after (command stat -f%z "$file")
            set -a formatted $file
            set -a formatted_before $before
            set -a formatted_after $after
        else
            rm -f "$file.tmp"
            set -a failed $file
        end
    end

    echo

    if test -n "$formatted"
        gum style --foreground 40 --bold "✓ formatted: (count $formatted) file(s)"
        set -l i 0
        for f in $formatted
            set i (math $i + 1)
            set -l before $formatted_before[$i]
            set -l after $formatted_after[$i]
            set -l diff (math $after - $before)

            if test $diff -eq 0
                gum join --horizontal \
                    (gum style --foreground 48 "  $f ") \
                    (gum style --foreground 245 "(no change)")
            else if test $diff -gt 0
                gum join --horizontal \
                    (gum style --foreground 48 "  $f ") \
                    (gum style --foreground 220 "+"(_pjson_human_size $diff))
            else
                set -l abs (math -- -1 \* $diff)
                gum join --horizontal \
                    (gum style --foreground 48 "  $f ") \
                    (gum style --foreground 45 "-"(_pjson_human_size $abs))
            end
        end
    end

    if test -n "$failed"
        if test -n "$formatted"
            echo
        end
        gum style --foreground 203 --bold "✗ failed:"
        for f in $failed
            gum style --foreground 210 "  $f"
        end
    end
end

function _pjson_human_size --description 'Convert bytes to human-readable size'
    set -l bytes $argv[1]
    if test $bytes -ge 1073741824
        printf "%.1f GB" (math $bytes / 1073741824)
    else if test $bytes -ge 1048576
        printf "%.1f MB" (math $bytes / 1048576)
    else if test $bytes -ge 1024
        printf "%.1f KB" (math $bytes / 1024)
    else
        printf "%d B" $bytes
    end
end
