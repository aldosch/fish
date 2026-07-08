function normalise-audio
    if test (count $argv) -ne 1
        echo "usage: normalise-audio /path/to/file.(mp4|mov|mkv|m4a|wav)"
        return 1
    end

    set in "$argv[1]"
    if not test -f "$in"
        echo "error: file not found: $in"
        return 1
    end

    set dir (dirname -- "$in")
    set base (basename -- "$in")
    set name (string split -r -m1 . "$base")[1]
    set ext (string split -r -m1 . "$base")[2]
    if test -z "$ext"
        set ext mp4
    end

    set tmp "$dir/.$name.normalising.$ext"
    set out "$dir/$base"

    # Build an available -original name (avoid clobbering)
    set trashdir "$HOME/.Trash"
    set orig_base "$name-original.$ext"
    set orig_path "$trashdir/$orig_base"
    set i 1
    while test -e "$orig_path"
        set orig_path "$trashdir/$name-original-$i.$ext"
        set i (math $i + 1)
    end

    # Normalize audio; keep video stream
    ffmpeg -hide_banner -y -i "$in" \
        -c:v copy \
        -af "loudnorm=I=-16:LRA=11:TP=-1.5" \
        -c:a aac -b:a 192k \
        "$tmp"
    if test $status -ne 0
        echo "error: ffmpeg failed"
        test -f "$tmp"; and rm -f "$tmp"
        return 1
    end

    # Move original to Trash as *-original*, replace with normalized
    mkdir -p "$trashdir"
    mv -f "$in" "$orig_path"
    if test $status -ne 0
        echo "error: failed moving original to Trash"
        rm -f "$tmp"
        return 1
    end

    mv -f "$tmp" "$out"
end
