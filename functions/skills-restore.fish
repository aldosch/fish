# skills-restore - restore globally installed agent skills from ~/.agents/.skill-lock.json
#
# Usage:
#   skills-restore          - restore all skills from lockfile
#   skills-restore --update - restore + update to latest versions
#
# Skills with sourceType "local" point to private repos. If the repo is not
# accessible on this machine, the install will fail non-fatally. A notice is
# printed with remediation steps.
#
# The lockfile lives at ~/.config/agents/.skill-lock.json (tracked in dotfiles).
# ~/.agents is a symlink to ~/.config/agents.

function skills-restore
    if not type -q gum
        echo "Error: gum is not installed. Install with 'brew install gum'"
        return 1
    end

    if not type -q npx
        echo "Error: npx not found. Ensure Node.js is installed."
        return 1
    end

    _aldo_dracula_apply_palette

    set -l do_update 0
    for arg in $argv
        switch $arg
            case --update -u
                set do_update 1
        end
    end

    set -l lockfile "$HOME/.agents/.skill-lock.json"

    if not test -f "$lockfile"
        gum style --foreground $p_red "  ✗ Lockfile not found: $lockfile"
        return 1
    end

    # --- header ---
    echo
    gum style --bold --foreground $p_purple --border rounded --border-foreground $p_purple \
        --padding "0 2" --align center \
        "skills-restore" \
        (gum style --faint --foreground $p_muted "restoring from .skill-lock.json")
    echo

    # --- collect local-source skills for post-run notice ---
    # Parse sourceType=local skills from lockfile using python (available on macOS)
    set -l local_skills (python3 -c "
import json, sys
with open('$lockfile') as f:
    data = json.load(f)
for name, info in data.get('skills', {}).items():
    if info.get('sourceType') == 'local':
        print(name + '|' + info.get('source', '') + '|' + info.get('sourceUrl', ''))
" 2>/dev/null)

    # --- run restore ---
    set -l t_start (date +%s)
    set -l tmplog (mktemp /tmp/skills-restore-XXXXXX)
    set -l exitfile {$tmplog}.exit

    fish -c "npx skills experimental_install -g -y >$tmplog 2>&1; echo \$status >$exitfile" &
    set -l bg_pid $last_pid

    # spinner while running
    set -l frames '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'
    set -l n_frames (count $frames)
    set -l i 1
    printf '\033[?25l'
    while not test -f $exitfile
        set -l frame $frames[$i]
        printf '\r\033[K%s' (gum join --horizontal \
            (gum style --foreground $p_purple " $frame") \
            (gum style --foreground $p_muted "  Restoring skills..."))
        set i (math "($i % $n_frames) + 1")
        sleep 0.1
    end
    printf '\r\033[K'
    printf '\033[?25h'

    wait $bg_pid 2>/dev/null
    set -l exit_code (string trim (cat $exitfile 2>/dev/null; or echo 1))
    set -l t_end (date +%s)
    set -l elapsed (math "$t_end - $t_start")
    if test $elapsed -lt 60
        set elapsed_str "$elapsed"s
    else
        set elapsed_str (math "floor($elapsed / 60)")m(math "$elapsed % 60")s
    end

    # parse installed count from output
    set -l installed_count (grep -c "Installed\|installed\|✓\|Added" $tmplog 2>/dev/null; or echo 0)

    if test "$exit_code" = "0"
        gum join --horizontal \
            (gum style --foreground $p_green "  ✓") \
            (gum style --foreground $p_fg " Skills restored") \
            (gum style --foreground $p_muted " ($elapsed_str)")
    else
        gum join --horizontal \
            (gum style --foreground $p_orange "  ▲") \
            (gum style --foreground $p_fg " Skills restore completed with warnings") \
            (gum style --foreground $p_muted " ($elapsed_str)")
    end

    rm -f $tmplog $exitfile

    # --- update step ---
    if test $do_update -eq 1
        echo
        set -l t_u_start (date +%s)
        gum spin --spinner dot \
            --spinner.foreground $p_purple \
            --title.foreground $p_muted \
            --title "  Updating skills to latest..." \
            -- fish -c "npx skills update -g -y" >/dev/null 2>&1
        set -l u_code $status
        set -l t_u_end (date +%s)
        set -l u_elapsed (math "$t_u_end - $t_u_start")
        if test $u_elapsed -lt 60
            set -l u_elapsed_str "$u_elapsed"s
        else
            set -l u_elapsed_str (math "floor($u_elapsed / 60)")m(math "$u_elapsed % 60")s
        end
        if test $u_code -eq 0
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " Skills updated") \
                (gum style --foreground $p_muted " ($u_elapsed_str)")
        else
            gum join --horizontal \
                (gum style --foreground $p_red "  ✗") \
                (gum style --foreground $p_fg " Skills update failed") \
                (gum style --foreground $p_muted " ($u_elapsed_str)")
        end
    end

    # --- notice for private-source skills ---
    if test (count $local_skills) -gt 0
        echo
        gum style --foreground $p_orange --bold "  ▸ Private-source skills"
        gum style --foreground $p_muted \
            "  The following skills come from private repos and may not have restored"
        gum style --foreground $p_muted \
            "  automatically. Check the output above and reinstall manually if needed."
        echo
        for entry in $local_skills
            set -l parts (string split "|" $entry)
            set -l skill_name $parts[1]
            set -l source $parts[2]
            set -l source_url $parts[3]
            gum join --horizontal \
                (gum style --foreground $p_yellow "    •") \
                (gum style --foreground $p_fg " $skill_name") \
                (gum style --foreground $p_muted "  ← $source")
            gum style --foreground $p_muted \
                "      To fix: clone the repo, then run:"
            gum style --foreground $p_cyan \
                "        npx skills add /path/to/repo@$skill_name -g"
            gum style --foreground $p_muted \
                "      Repo: $source_url"
            echo
        end
    end

    echo
end
