# brew - wrapper that keeps nix/modules/apps.nix in sync on install/uninstall
#
# Intercepts only:
#   - `brew install <pkgs>` / `brew i <pkgs>` (shorthand preserved)
#   - `brew install --cask <pkgs>` / `brew install --casks <pkgs>`
#   - `brew uninstall <pkgs>` / `brew rm <pkgs>` / `brew remove <pkgs>`
#   - `brew uninstall --cask <pkgs>` etc.
#
# On install: asks whether to add to the HOST-SPECIFIC list in apps.nix
#   (minOnlyBrews/minOnlyCasks or bookOnlyBrews/bookOnlyCasks, never common).
#   Yes → install + edit apps.nix + auto-commit.
#   No  → install only (temporary; cleanup = "zap" removes on next nixx apply).
#
# On uninstall: asks whether to remove from the host-specific list.
#   Yes → uninstall + edit apps.nix + auto-commit.
#   No  → uninstall only (still declared; reinstalled on next nixx apply).
#
# Packages already declared anywhere in apps.nix (common or host-specific):
#   install passes through silently (already managed).
#   uninstall from common list: warns that it's shared (manual edit needed).
#
# Everything else (update, tap, list, cleanup, etc.) passes through untouched.

function brew --wraps brew
    # --- `brew i` shorthand → `brew install` ---
    if test "$argv[1]" = i
        set argv install $argv[2..-1]
    end

    set -l sub $argv[1]
    set -l rest
    if test (count $argv) -gt 1
        set rest $argv[2..-1]
    end

    # --- classify subcommand ---
    set -l mode ""
    if test "$sub" = install
        set mode install
    else if contains -- $sub uninstall rm remove
        set mode remove
    else
        command brew $argv
        return
    end

    # --- detect --cask / --casks ---
    set -l is_cask 0
    for arg in $rest
        if test "$arg" = --cask; or test "$arg" = --casks
            set is_cask 1
            break
        end
    end

    # --- collect package specs (skip flags, URLs, paths) ---
    set -l specs
    for arg in $rest
        if string match -q -- '--*' $arg
            continue
        end
        if string match -q -- 'http*' $arg
            continue
        end
        if string match -q -- '/*' $arg; or string match -q -- './*' $arg
            continue
        end
        set -a specs $arg
    end

    # no package args → pass through
    if test (count $specs) -eq 0
        command brew $argv
        return
    end

    # non-interactive (no TTY) → pass through
    if not test -t 0; or not test -t 1
        command brew $argv
        return
    end

    # --- determine host-specific list ---
    set -l hn $hostname
    set -l list_name
    set -l surface_desc "formula"
    if test $is_cask -eq 1
        set surface_desc "cask"
        if test "$hn" = book
            set list_name bookOnlyCasks
        else
            set list_name minOnlyCasks
        end
    else
        if test "$hn" = book
            set list_name bookOnlyBrews
        else
            set list_name minOnlyBrews
        end
    end

    set -l apps_nix ~/.config/nix/modules/apps.nix

    if test "$mode" = install
        # --- check which specs are already declared (anywhere in apps.nix) ---
        set -l undeclared
        for spec in $specs
            if not grep -Fq -- "\"$spec\"" $apps_nix 2>/dev/null
                set -a undeclared $spec
            end
        end

        # all already declared → just install
        if test (count $undeclared) -eq 0
            command brew $argv
            return $status
        end

        # confirm
        _pkg_msg info "Undeclared $surface_desc(s): "(string join ", " $undeclared)
        set -l do_add 0
        if _brew_confirm "Add to apps.nix ($list_name)?  (No = temporary, cleaned by next nixx)"
            set do_add 1
        end

        # run real install
        command brew $argv
        set -l rc $status
        if test $rc -ne 0
            return $rc
        end

        if test $do_add -eq 1
            set -l added
            for spec in $undeclared
                if _brew_add_to_nix $apps_nix $list_name $spec
                    set -a added $spec
                end
            end
            if test (count $added) -gt 0
                set -l committed 0
                git -C ~/.config add nix/modules/apps.nix
                and git -C ~/.config commit -m "brew: add "(string join ", " $added) -- nix/modules/apps.nix
                and set committed 1
                if test $committed -eq 1
                    _pkg_msg ok "Added to apps.nix ($list_name): "(string join ", " $added)" (committed)"
                else
                    _pkg_msg warn "Added to apps.nix ($list_name): "(string join ", " $added)" (commit failed — staged, commit manually)"
                end
            end
        else
            _pkg_msg warn "Temporary install (cleanup = zap will remove on next nixx apply)"
        end

    else
        # --- uninstall mode ---
        # split: in host-specific list vs in common (not host-specific)
        set -l in_host_list
        set -l in_common
        for spec in $specs
            if _brew_in_list $apps_nix $list_name $spec
                set -a in_host_list $spec
            else if grep -Fq -- "\"$spec\"" $apps_nix 2>/dev/null
                set -a in_common $spec
            end
        end

        # nothing in host-specific list → just uninstall
        if test (count $in_host_list) -eq 0
            command brew $argv
            set -l rc $status
            if test $rc -ne 0
                return $rc
            end
            if test (count $in_common) -gt 0
                _pkg_msg warn "In common list (affects both machines): "(string join ", " $in_common)" — edit apps.nix manually to remove"
            end
            return 0
        end

        # confirm removal from host-specific list
        _pkg_msg info "In $list_name: "(string join ", " $in_host_list)
        set -l do_remove 0
        if _brew_confirm "Remove from apps.nix ($list_name)?  (No = keep declared, reinstalled by next nixx)"
            set do_remove 1
        end

        # run real uninstall
        command brew $argv
        set -l rc $status
        if test $rc -ne 0
            return $rc
        end

        if test $do_remove -eq 1
            set -l removed
            for spec in $in_host_list
                if _brew_remove_from_nix $apps_nix $list_name $spec
                    set -a removed $spec
                end
            end
            if test (count $removed) -gt 0
                set -l committed 0
                git -C ~/.config add nix/modules/apps.nix
                and git -C ~/.config commit -m "brew: remove "(string join ", " $removed) -- nix/modules/apps.nix
                and set committed 1
                if test $committed -eq 1
                    _pkg_msg ok "Removed from apps.nix ($list_name): "(string join ", " $removed)" (committed)"
                else
                    _pkg_msg warn "Removed from apps.nix ($list_name): "(string join ", " $removed)" (commit failed — modified, commit manually)"
                end
            end
        else
            _pkg_msg warn "Still declared in apps.nix — will be reinstalled on next nixx apply"
        end
    end

    return 0
end

# --- confirm helper (read fallback if gum not available) ---
function _brew_confirm
    set -l prompt $argv[1]
    if type -q gum
        gum confirm --selected.background $p_purple "  $prompt"
    else
        echo "  $prompt [y/N]"
        read -l answer
        test "$answer" = y; or test "$answer" = Y
    end
end

# --- check if a package name is in a specific list block in apps.nix ---
# Usage: _brew_in_list <file> <list_name> <pkg>
# Returns 0 if found, 1 if not.
function _brew_in_list
    set -l file $argv[1]
    set -l list $argv[2]
    set -l pkg $argv[3]
    awk -v list="$list" -v pkg="\"$pkg\"" '
        index($0, list " = [") > 0 { in_block=1 }
        in_block && index($0, "];") > 0 { in_block=0 }
        in_block && index($0, pkg) > 0 { found=1 }
        END { exit (found ? 0 : 1) }
    ' $file
    return $status
end

# --- add a package to a list block in apps.nix ---
# Usage: _brew_add_to_nix <file> <list_name> <pkg>
# Inserts "      \"pkg\"" before the closing ]; of the block.
function _brew_add_to_nix
    set -l file $argv[1]
    set -l list $argv[2]
    set -l pkg $argv[3]
    set -l tmp (mktemp)
    awk -v list="$list" -v pkg="\"$pkg\"" '
        index($0, list " = [") > 0 { in_block=1 }
        in_block && index($0, "];") > 0 { print "      " pkg; in_block=0 }
        { print }
    ' $file > $tmp
    and mv $tmp $file
    return $status
end

# --- remove a package from a list block in apps.nix ---
# Usage: _brew_remove_from_nix <file> <list_name> <pkg>
# Deletes the line containing "pkg" within the block.
function _brew_remove_from_nix
    set -l file $argv[1]
    set -l list $argv[2]
    set -l pkg $argv[3]
    set -l tmp (mktemp)
    awk -v list="$list" -v pkg="\"$pkg\"" '
        index($0, list " = [") > 0 { in_block=1 }
        in_block && index($0, "];") > 0 { in_block=0 }
        in_block && index($0, pkg) > 0 { next }
        { print }
    ' $file > $tmp
    and mv $tmp $file
    return $status
end
