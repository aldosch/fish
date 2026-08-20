# npm - wrapper that redirects global installs to pnpm
#
# pnpm is the canonical Node global package manager in this config (see
# pnpm/globals.txt). npm globals are limited to npm/pnpm/corepack, which are
# managed by fnm/corepack. So any `npm install -g <pkg>` (or variant) for
# anything else is redirected to `pnpm add -g <pkg>`, which in turn keeps
# pnpm/globals.txt in sync and auto-commits.
#
# Intercepts only:
#   - `npm install -g <pkgs>` / `npm i -g` / `npm add -g` (+ --global variants)
#   - `npm uninstall -g <pkgs>` / `npm rm -g` / `npm remove -g` / `npm un -g`
#
# For npm/pnpm/corepack: passes through to the real npm (fnm-managed).
# Everything else (non-global commands, other subcommands) passes through
# to the real npm untouched.

function npm --wraps npm
    set -l sub $argv[1]
    set -l rest
    if test (count $argv) -gt 1
        set rest $argv[2..-1]
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
        command npm $argv
        return
    end

    # --- subcommand classification ---
    set -l install_subs install i add
    set -l remove_subs uninstall rm remove un

    set -l mode ""
    if contains -- $sub $install_subs
        set mode install
    else if contains -- $sub $remove_subs
        set mode remove
    end

    # global flag but not install/remove (e.g. update -g, list -g) → pass through
    if test -z "$mode"
        command npm $argv
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

    # no package args → pass through
    if test (count $specs) -eq 0
        command npm $argv
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

    # --- check for fnm-managed packages (npm/pnpm/corepack) ---
    set -l managed npm pnpm corepack
    for name in $names
        if contains -- $name $managed
            # pass through to real npm for managed packages
            command npm $argv
            return
        end
    end

    # --- redirect to pnpm ---
    if type -q gum
        gum style --foreground $p_muted "  → npm global → pnpm (pnpm is the canonical Node global manager)"
    else
        echo "  → redirecting to pnpm"
    end

    if test "$mode" = install
        pnpm add -g $specs
    else
        pnpm remove -g $specs
    end
    return $status
end
