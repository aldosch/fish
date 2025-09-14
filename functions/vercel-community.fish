function vercel-community
    set post_number $argv[1]

    if test -z "$post_number"
        set post_number (pbpaste)
    end

    if not string match -qr '^[0-9]+$' "$post_number"
        echo "😬 clipboard should contain a valid numeric post number."
        return 1
    end

    set COMMUNITY_DIR "$HOME/vercel/community/$post_number"

    if not test -d "$COMMUNITY_DIR"
        echo "✨ new community post: $post_number"
        mkdir -p "$COMMUNITY_DIR"
    else
        echo "👀 opening community post: $post_number"
    end

    cd "$COMMUNITY_DIR"
end