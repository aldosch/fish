function git --wraps git
    _aldo_dracula_apply_palette

    # Only intercept `git clone` with HTTPS GitHub URLs.
    # Converts to SSH and tries that first, falls back to HTTPS on failure.
    # Everything else passes through untouched.

    if test (count $argv) -lt 2; or test "$argv[1]" != clone
        command git $argv
        return
    end

    # Scan clone args for an HTTPS GitHub URL
    set -l url_index 0
    set -l https_url ""
    for i in (seq 2 (count $argv))
        if string match -qr '^https://github\.com/' -- $argv[$i]
            set url_index $i
            set https_url $argv[$i]
            break
        end
    end

    # No HTTPS GitHub URL found — pass through as-is
    if test $url_index -eq 0
        command git $argv
        return
    end

    # Convert: https://github.com/owner/repo[.git] → git@github.com:owner/repo.git
    set -l path (string replace 'https://github.com/' '' -- $https_url)
    set path (string replace -r '\.git$' '' -- $path)
    set -l ssh_url "git@github.com:$path.git"

    # Build new argv with SSH URL swapped in
    set -l ssh_argv
    for i in (seq 2 (count $argv))
        if test $i -eq $url_index
            set -a ssh_argv $ssh_url
        else
            set -a ssh_argv $argv[$i]
        end
    end

    # Try SSH first
    set_color $p_yellow
    echo "→ Trying SSH: $ssh_url"
    set_color normal
    command git clone $ssh_argv
    and return

    # Fall back to HTTPS
    set_color $p_red
    echo "→ SSH failed, falling back to HTTPS"
    set_color normal
    command git clone $argv[2..]
end
