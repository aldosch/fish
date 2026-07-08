function fix-audio
    if test (count $argv) -ne 1
        echo "usage: fix-audio /path/to/file.mp4"
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
        set base "$name.$ext"
    end

    set tmp_out "$dir/$name-adjusted.$ext"
    set final_out "$dir/$base"
    set orig_renamed "$dir/$name-original.$ext"

    # 1) Render adjusted audio to a temp file
    ffmpeg -hide_banner -y -i "$in" \
        -c:v copy \
        -af "pan=stereo|FL=FL|FR=FL,loudnorm=I=-16:LRA=11:TP=-1.5:dual_mono=true" \
        -c:a aac -b:a 192k \
        "$tmp_out"

    if test $status -ne 0
        echo "error: ffmpeg failed; original left untouched"
        return 1
    end

    # 2) Rename original to -original alongside it (so we can keep the final name for the adjusted file)
    #    Use mv so it stays on the same volume and preserves metadata as per normal POSIX behavior.
    mv -n "$in" "$orig_renamed"
    if test $status -ne 0
        echo "error: could not rename original to: $orig_renamed"
        rm -f "$tmp_out"
        return 1
    end

    # 3) Move adjusted into the original’s name
    mv -f "$tmp_out" "$final_out"
    if test $status -ne 0
        echo "error: could not place adjusted file at original path; restoring original name"
        mv -f "$orig_renamed" "$in"
        rm -f "$tmp_out"
        return 1
    end

    # 4) Send the renamed original to Trash (not permanent delete)
    #    Finder’s ‘delete’ moves files to Trash.
    osascript -ss -e 'tell application "Finder" to delete POSIX file '"\"$orig_renamed\"" > /dev/null

    # Done
end
