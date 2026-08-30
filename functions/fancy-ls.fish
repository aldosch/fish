# lss -- shared impl for ls/lst/lss/lsm/lsc
#
# Usage: lss [--sort=<field>] [--reverse] [--show-size] [--show-date=<mod|created>] [-a|--all] [depth]
#
# Called via aliases: ls lst lss lsm lsc
function fancy-ls
    set -l depth 1
    set -l sort_field name
    set -l do_reverse 0
    set -l show_size 0
    set -l show_date ""
    set -l show_all 0

    argparse 'sort=' 'reverse' 'show-size' 'show-date=' 'a/all' -- $argv
    or return

    if set -q _flag_sort
        set sort_field $_flag_sort
    end
    if set -q _flag_reverse
        set do_reverse 1
    end
    if set -q _flag_show_size
        set show_size 1
    end
    if set -q _flag_show_date
        set show_date $_flag_show_date
    end
    if set -q _flag_a
        set show_all 1
    end

    # Remaining positional arg = depth
    if test (count $argv) -gt 0
        set depth $argv[1]
    end

    set -l eza_args \
        --tree \
        --level=$depth \
        --icons=auto \
        --hyperlink \
        --sort=$sort_field \
        --group-directories-first

    # -a shows dotfiles; drop --git-ignore so ignored dotfiles (.git, node_modules, etc.) appear too
    if test $show_all -eq 1
        set eza_args $eza_args --all
    else
        set eza_args $eza_args --git-ignore
    end

    if test $do_reverse -eq 1
        set eza_args $eza_args --reverse
    end

    if test $show_size -eq 1 -o -n "$show_date"
        set eza_args $eza_args \
            --long \
            --no-permissions \
            --no-user \
            --header
        if test $show_size -eq 1
            set eza_args $eza_args --total-size
        else
            set eza_args $eza_args --no-filesize
        end
        if test -n "$show_date"
            set eza_args $eza_args --modified --time-style=relative
            if test "$show_date" = created
                set eza_args $eza_args --created
            end
        else
            set eza_args $eza_args --no-time
        end
    end

    eza $eza_args
end
