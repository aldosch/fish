# pnpm - wrapper that keeps pnpm/globals.txt in sync on global add/remove
#
# Intercepts only:
#   - `pnpm add -g <pkgs>` / `pnpm install -g` / `pnpm i -g` (+ --global variants)
#   - `pnpm remove -g <pkgs>` / `pnpm rm -g` / `pnpm uninstall -g` / `pnpm un -g`
#   - `pnpm self-update` (refused — see below)
#
# On global install: appends package names to pnpm/globals.txt and auto-commits.
# On global remove: deletes matching lines and auto-commits.
# Refuses npm/pnpm/corepack (managed by fnm/corepack — don't touch manually).
#
# Everything else (update -g, install --dir, list, run, etc.) passes through
# to the real pnpm untouched.

function pnpm --wraps pnpm
    set -l sub $argv[1]
    set -l rest
    if test (count $argv) -gt 1
        set rest $argv[2..-1]
    end

    # --- self-update guard ---
    if test "$sub" = self-update
        echo "pnpm self-update installs a standalone pnpm into ~/Library/pnpm/" >&2
        echo "that shadows the corepack-managed one and falls behind." >&2
        echo "pnpm stays current via: corepack prepare pnpm@latest --activate" >&2
        echo "(this runs automatically in nixx)" >&2
        return 1
    end

    # --- check for -g / --global flag ---
    set -l is_global 0
    for arg in $rest
        if test "$arg" = -g; or test "$arg" = --global
            set is_global 1
            break
        end
    end
    if test $is_global -eq 0
        command pnpm $argv
        return
    end

    # --- subcommand classification ---
    set -l install_subs add install i
    set -l remove_subs remove rm uninstall un

    set -l mode ""
    if contains -- $sub $install_subs
        set mode install
    else if contains -- $sub $remove_subs
        set mode remove
    end

    # global flag but not add/remove (e.g. update -g, list -g) → pass through
    if test -z "$mode"
        command pnpm $argv
        return
    end

    # --- collect package specs (skip flags) ---
    set -l specs
    for arg in $rest
        if test "$arg" = -g; or test "$arg" = --global
            continue
        end
        if string match -q -- '-*' $arg
            continue
        end
        set -a specs $arg
    end

    # no package args → pass through (let pnpm prompt or error)
    if test (count $specs) -eq 0
        command pnpm $argv
        return
    end

    # --- extract package names from specs (strip @version) ---
    set -l names
    for spec in $specs
        set -l name $spec
        if string match -q -- '@*' $spec
            set name (string replace -r '^(@[^@/]+/[^@]+)@.*$' '$1' -- $spec)
        else
            set name (string replace -r '^([^@]+)@.*$' '$1' -- $spec)
        end
        set -a names $name
    end

    # --- refuse fnm/corepack-managed packages ---
    set -l managed npm pnpm corepack
    set -l refused
    for name in $names
        if contains -- $name $managed
            set -a refused $name
        end
    end
    if test (count $refused) -gt 0
        set -l verb add
        if test "$mode" = remove
            set verb remove
        end
        echo "Refusing to $verb global: "(string join ", " $refused) >&2
        echo "These are managed by fnm/corepack — don't install or remove them manually." >&2
        return 1
    end

    # --- run the real command (original args, untouched) ---
    command pnpm $argv
    set -l rc $status
    if test $rc -ne 0
        return $rc
    end

    # --- update canonical list ---
    set -l canonical ~/.config/pnpm/globals.txt

    if test "$mode" = install
        set -l to_add
        for name in $names
            if not grep -Fxq -- "$name" $canonical 2>/dev/null
                set -a to_add $name
            end
        end

        if test (count $to_add) -eq 0
            _pnpm_msg ok "Already in pnpm/globals.txt"
            return 0
        end

        for name in $to_add
            echo "$name" >> $canonical
        end

        set -l committed 0
        git -C ~/.config add pnpm/globals.txt
        and git -C ~/.config commit -m "pnpm: add "(string join ", " $to_add) -- pnpm/globals.txt
        and set committed 1

        if test $committed -eq 1
            _pnpm_msg ok "Added to pnpm/globals.txt: "(string join ", " $to_add)" (committed)"
        else
            _pnpm_msg warn "Added to pnpm/globals.txt: "(string join ", " $to_add)" (commit failed — staged, commit manually)"
        end
    else
        # remove
        set -l to_remove
        for name in $names
            if grep -Fxq -- "$name" $canonical 2>/dev/null
                set -a to_remove $name
            end
        end

        if test (count $to_remove) -eq 0
            _pnpm_msg ok "Not in pnpm/globals.txt"
            return 0
        end

        for name in $to_remove
            set -l tmp (mktemp)
            grep -Fxv -- "$name" $canonical > $tmp
            mv $tmp $canonical
        end

        set -l committed 0
        git -C ~/.config add pnpm/globals.txt
        and git -C ~/.config commit -m "pnpm: remove "(string join ", " $to_remove) -- pnpm/globals.txt
        and set committed 1

        if test $committed -eq 1
            _pnpm_msg ok "Removed from pnpm/globals.txt: "(string join ", " $to_remove)" (committed)"
        else
            _pnpm_msg warn "Removed from pnpm/globals.txt: "(string join ", " $to_remove)" (commit failed — modified, commit manually)"
        end
    end

    return 0
end

# --- output helper (plain text fallback if gum not available) ---
function _pnpm_msg
    set -l kind $argv[1]
    set -l text $argv[2..-1]
    set -l symbol "  ·"
    set -l color $p_muted
    switch $kind
        case ok
            set symbol "  ✓"
            set color $p_green
        case warn
            set symbol "  ▸"
            set color $p_orange
    end
    if type -q gum
        gum join --horizontal \
            (gum style --foreground $color "$symbol") \
            (gum style --foreground $p_fg " $text")
    else
        echo "$symbol $text"
    end
end
