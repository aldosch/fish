# __drift_scans - pure scan functions for parallel drift detection
#
# Each scan function:
#   - Gathers data and computes drift (no gum, no colors, no interaction)
#   - Outputs structured lines to stdout (TSV with tab separators):
#       ITEM\t<kind>\t<type>\t<name>\t<extra>     a drift item needing action
#       DIFF\t<line>                               diff content (generated files)
#       META\t<key>=<value>                        metadata (generated files paths)
#       ERROR\t<message>                           scan error (could not gather data)
#       MSG\t<message>                             informational message (model catalog)
#   - Exit codes: 0 = clean, 1 = drift found, 2 = scan error
#
# Sourced by nixx-drift.fish DAG tasks via:
#   source <this_file>; and __drift_scan_<surface> <args>

# -------------------------------------------------------------------------
# Shared helpers
# -------------------------------------------------------------------------

# Parse a canonical package list: strip comments and blank lines, sort.
function __drift_parse_list
    test -f $argv[1]; or return 0
    for line in (cat $argv[1])
        set -l trimmed (string trim -- $line)
        test -z "$trimmed"; and continue
        string match -q -- '#*' $trimmed; and continue
        echo $trimmed
    end | sort
end

# Echo 1 if the canonical list has at least one real (non-comment) entry, else 0.
function __drift_list_has_entries
    set -l entries (__drift_parse_list $argv[1])
    if test (count $entries) -gt 0
        echo 1
    else
        echo 0
    end
end

# Extract `.name` values from a captured `nix eval --json` log.
# nix prints warnings to the same stream, so grab the single JSON array line
# (starts with `[`) and feed only that to jq.
function __drift_json_names
    test -f $argv[1]; or return 0
    set -l json_line (grep -m1 '^\[' $argv[1] 2>/dev/null)
    test -n "$json_line"; or return 0
    printf '%s\n' $json_line | jq -r '.[].name' 2>/dev/null | sort
end

# -------------------------------------------------------------------------
# Surface 1: Homebrew brews and casks (via nix eval, 2 evals in parallel)
# -------------------------------------------------------------------------

function __drift_scan_brew
    set -l config_dir $argv[1]
    set -l nix_dir $argv[2]
    set -l hn $argv[3]

    # Run nix evals in parallel (the slow part, up to 90s each uncached).
    # Each writes JSON to its own logfile + exit code to an exitfile.
    set -l ts (date +%s)
    set -l brews_log /tmp/drift-scan-brews-$ts.log
    set -l casks_log /tmp/drift-scan-casks-$ts.log
    set -l brews_exit /tmp/drift-scan-brews-$ts.exit
    set -l casks_exit /tmp/drift-scan-casks-$ts.exit

    fish -c "cd $nix_dir && nix eval '.#darwinConfigurations.$hn.config.homebrew.brews' --extra-experimental-features 'nix-command flakes' --json >$brews_log 2>&1; echo \$status >$brews_exit" &
    set -l brews_pid $last_pid

    fish -c "cd $nix_dir && nix eval '.#darwinConfigurations.$hn.config.homebrew.casks' --extra-experimental-features 'nix-command flakes' --json >$casks_log 2>&1; echo \$status >$casks_exit" &
    set -l casks_pid $last_pid

    # While nix evals run, gather brew state (fast, ~2-3s total)
    set -l leaves_brews_raw (brew leaves 2>/dev/null)
    set -l all_installed_brews (brew list --formula 2>/dev/null | sort)
    set -l installed_casks (brew list --cask 2>/dev/null | sort)

    # Wait for both nix evals
    wait $brews_pid 2>/dev/null
    wait $casks_pid 2>/dev/null

    set -l brews_rc (string trim (cat $brews_exit 2>/dev/null; or echo 1))
    set -l casks_rc (string trim (cat $casks_exit 2>/dev/null; or echo 1))
    rm -f $brews_exit $casks_exit

    # Parse declared lists
    set -l declared_brews
    if test $brews_rc -eq 0
        set declared_brews (__drift_json_names $brews_log)
    end
    rm -f $brews_log

    set -l declared_casks
    if test $casks_rc -eq 0
        set declared_casks (__drift_json_names $casks_log)
    end
    rm -f $casks_log

    if test -z "$declared_brews" -a -z "$declared_casks"
        if test $brews_rc -eq 124 -o $casks_rc -eq 124
            printf 'ERROR\tnix eval timed out\n'
        else
            printf 'ERROR\tnix eval failed (rc=%s/%s)\n' $brews_rc $casks_rc
        end
        return 2
    end

    # Normalize names (strip tap prefixes)
    set -l declared_brews_normalized
    for pkg in $declared_brews
        set declared_brews_normalized $declared_brews_normalized (string replace -ra '^.+/' '' $pkg)
    end

    set -l leaves_brews_normalized
    for pkg in $leaves_brews_raw
        set leaves_brews_normalized $leaves_brews_normalized (string replace -ra '^.+/' '' $pkg)
    end

    set -l declared_casks_normalized
    for pkg in $declared_casks
        set declared_casks_normalized $declared_casks_normalized (string replace -ra '^.+/' '' $pkg)
    end

    set -l found_drift 0

    # Extra brews (leaf-installed but not declared)
    for i in (seq (count $leaves_brews_raw))
        set -l pkg $leaves_brews_raw[$i]
        set -l pkg_short $leaves_brews_normalized[$i]
        if not contains -- $pkg_short $declared_brews_normalized
            printf 'ITEM\textra\tbrew-formula\t%s\t\n' $pkg
            set found_drift 1
        end
    end

    # Missing brews (declared but not in full installed list)
    for i in (seq (count $declared_brews))
        set -l pkg $declared_brews[$i]
        set -l pkg_short $declared_brews_normalized[$i]
        if not contains -- $pkg_short $all_installed_brews
            printf 'ITEM\tmissing\tbrew-formula\t%s\tdeclared in apps.nix but not installed\n' $pkg
            set found_drift 1
        end
    end

    # Extra casks
    for pkg in $installed_casks
        if not contains -- $pkg $declared_casks_normalized
            printf 'ITEM\textra\tbrew-cask\t%s\t\n' $pkg
            set found_drift 1
        end
    end

    # Missing casks
    for i in (seq (count $declared_casks))
        set -l pkg $declared_casks[$i]
        set -l pkg_short $declared_casks_normalized[$i]
        if not contains -- $pkg_short $installed_casks
            printf 'ITEM\tmissing\tbrew-cask\t%s\tdeclared in apps.nix but not installed\n' $pkg
            set found_drift 1
        end
    end

    if test $found_drift -eq 0
        return 0
    end
    return 1
end

# -------------------------------------------------------------------------
# Surface 2: pnpm globals
# -------------------------------------------------------------------------

function __drift_scan_pnpm
    set -l config_dir $argv[1]
    set -l canonical_file $config_dir/pnpm/globals.txt

    if not test -f $canonical_file
        printf 'ERROR\t%s not found\n' $canonical_file
        return 2
    end

    set -l declared (__drift_parse_list $canonical_file)

    # Guard against transient/empty read
    if test -z "$declared"; and test (__drift_list_has_entries $canonical_file) -eq 1
        printf 'ERROR\tCould not read pnpm/globals.txt\n'
        return 2
    end

    # Installed pnpm globals
    set -l pnpm_out (pnpm list -g --depth=0 --json 2>/dev/null)
    if test $status -ne 0
        printf 'ERROR\tCould not read pnpm global packages\n'
        return 2
    end
    set -l installed (echo $pnpm_out | jq -r '.[0].dependencies | keys[]' 2>/dev/null | sort)

    if test -z "$installed"
        printf 'ERROR\tCould not parse pnpm global packages\n'
        return 2
    end

    set -l found_drift 0

    # Extra: installed but not declared
    for pkg in $installed
        if not contains -- $pkg $declared
            printf 'ITEM\textra\tpnpm\t%s\t\n' $pkg
            set found_drift 1
        end
    end

    # Missing: declared but not installed
    for pkg in $declared
        if not contains -- $pkg $installed
            printf 'ITEM\tmissing\tpnpm\t%s\tin pnpm/globals.txt but not installed\n' $pkg
            set found_drift 1
        end
    end

    if test $found_drift -eq 0
        return 0
    end
    return 1
end

# -------------------------------------------------------------------------
# Surface 3: uv tools
# -------------------------------------------------------------------------

function __drift_scan_uv
    set -l config_dir $argv[1]
    set -l canonical_file $config_dir/uv/tools.txt

    if not test -f $canonical_file
        printf 'ERROR\t%s not found\n' $canonical_file
        return 2
    end

    set -l declared (__drift_parse_list $canonical_file)

    # Guard against transient/empty read
    if test -z "$declared"; and test (__drift_list_has_entries $canonical_file) -eq 1
        printf 'ERROR\tCould not read uv/tools.txt\n'
        return 2
    end

    # Installed uv tools: top-level lines only (sub-executables start with "- ")
    set -l installed (uv tool list 2>/dev/null | grep -v '^-' | grep -v '^\s*$' | awk '{print $1}' | sort)

    if test -z "$installed" -a (count $declared) -gt 0
        printf 'ERROR\tNo uv tools installed (but %d declared)\n' (count $declared)
        return 2
    end

    set -l found_drift 0

    # Extra: installed but not declared
    for pkg in $installed
        if not contains -- $pkg $declared
            printf 'ITEM\textra\tuv\t%s\t\n' $pkg
            set found_drift 1
        end
    end

    # Missing: declared but not installed
    for pkg in $declared
        if not contains -- $pkg $installed
            printf 'ITEM\tmissing\tuv\t%s\tin uv/tools.txt but not installed\n' $pkg
            set found_drift 1
        end
    end

    if test $found_drift -eq 0
        return 0
    end
    return 1
end

# -------------------------------------------------------------------------
# Surface 4: opencode plugin (node_modules is gitignored)
# -------------------------------------------------------------------------

function __drift_scan_opencode
    set -l config_dir $argv[1]
    set -l plugin_path $config_dir/opencode/node_modules/@opencode-ai/plugin/package.json

    if test -f "$plugin_path"
        return 0
    end

    printf 'ITEM\tmissing\topencode-plugin\t@opencode-ai/plugin\tdeclared in opencode/pnpm-lock.yaml but not installed (node_modules missing)\n'
    return 1
end

# -------------------------------------------------------------------------
# Surface 5: model catalog freshness (informational, no install/remove)
# -------------------------------------------------------------------------

function __drift_scan_model_catalog
    if not type -q opencode-model-catalog-check
        printf 'ERROR\topencode-model-catalog-check function not found\n'
        return 2
    end

    set -l out (opencode-model-catalog-check 2>&1)
    set -l rc $status

    if test $rc -eq 0
        return 0
    else if test $rc -eq 2
        # Drift found (informational). Forward the check script's output lines.
        for line in $out
            printf 'MSG\t%s\n' $line
        end
        return 1
    else
        printf 'ERROR\tcheck failed (rc=%s): %s\n' $rc (string join ' ' -- $out)
        return 2
    end
end

# -------------------------------------------------------------------------
# Surface 6: opencode MCP commands (pnpx guard)
# -------------------------------------------------------------------------

function __drift_scan_mcp
    set -l config_dir $argv[1]
    set -l cfg $config_dir/opencode/opencode.json

    if not test -f $cfg
        printf 'ERROR\topencode/opencode.json not found\n'
        return 2
    end

    set -l found_drift 0

    # Walk every local MCP entry, print "name\tcommand" so we can detect pnpx
    set -l entries_raw (jq -r '
        .mcp // {} | to_entries[]
        | select(.value.type == "local")
        | .key + "\t" + ((.value.command // []) | join(" "))
    ' "$cfg" 2>/dev/null)

    for line in $entries_raw
        set -l parts (string split \t -- $line)
        set -l name $parts[1]
        set -l cmd $parts[2]
        set -l first_token (string split ' ' -- $cmd)[1]
        if test "$first_token" = pnpx
            printf 'ITEM\twrong-cmd\tmcp\t%s\tuses pnpx (broken under pnpm 11 for ESM pkgs)\n' $name
            set found_drift 1
        end
    end

    if test $found_drift -eq 0
        return 0
    end
    return 1
end

# -------------------------------------------------------------------------
# Surface 7: generated files (activation-script-managed configs)
# -------------------------------------------------------------------------

function __drift_scan_generated
    set -l config_dir $argv[1]
    set -l nix_dir $argv[2]

    # Ghostty config: nix/modules/ghostty.nix writes ~/.config/ghostty/config
    # via activation script; expected content at /etc/static/ghostty-expected
    set -l expected /etc/static/ghostty-expected
    set -l actual $config_dir/ghostty/config
    set -l source $nix_dir/modules/ghostty.nix

    if not test -f "$expected"
        # Module not applied yet, skip
        return 0
    end

    if not test -f "$actual"
        printf 'ITEM\tmissing\tgenerated\tghostty config\t%s not found\n' $actual
        printf 'META\tsource=%s\n' $source
        printf 'META\texpected=%s\n' $expected
        printf 'META\tactual=%s\n' $actual
        return 1
    end

    set -l diff_output (diff -u "$expected" "$actual" 2>/dev/null)
    set -l diff_rc $status

    if test $diff_rc -eq 0
        return 0
    end

    # Drift detected
    printf 'ITEM\tmodified\tgenerated\tghostty config\tmanually edited, diverged from nix-generated content\n'
    printf 'META\tsource=%s\n' $source
    printf 'META\texpected=%s\n' $expected
    printf 'META\tactual=%s\n' $actual
    for line in $diff_output
        printf 'DIFF\t%s\n' $line
    end

    return 1
end
