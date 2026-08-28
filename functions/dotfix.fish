# dotfix - interactive drift remediation
#
# Runs `nixx check` (the full 8-surface interactive drift check with gum
# choose/confirm prompts), then refreshes the background health state so
# the MOTD doesn't keep nagging about items you just resolved.
#
# Usage:
#   dotfix

function dotfix
    _aldo_dracula_apply_palette

    echo
    gum style --bold --foreground $p_purple --border rounded --border-foreground $p_purple \
        --padding "0 2" --align center \
        "dotfix" \
        (gum style --faint --foreground $p_muted "interactive drift remediation")
    echo

    nixx check
    set -l rc $status

    # Refresh background health state so the MOTD updates
    set -l notices_file ~/.local/state/dotfiles/notices.json
    if test -f "$notices_file"
        if test $rc -eq 0
            # All clean — clear notices
            jq -n --arg t (date -u +%Y-%m-%dT%H:%M:%S) \
                '{items:[],message:"",count:0,auto_fixed_count:0,generated_at:$t,last_shown:null}' >$notices_file
            echo
            gum join --horizontal \
                (gum style --foreground $p_green "  ✓") \
                (gum style --foreground $p_fg " all resolved, notices cleared")
        else
            # Still has drift — run health check to refresh state
            dotfiles-health
        end
    end

    echo
end
