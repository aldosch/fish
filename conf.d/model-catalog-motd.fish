# model-catalog-motd.fish - one-line notice for pending model pick proposals
#
# The daily maintenance model-catalog-sync task researches compelling new
# gateway models and files proposals in opencode/model-catalog.json
# ("proposed"). This motd surfaces them so the recommended picks actually
# get noticed: one subtle line in interactive shells, showing until the
# proposals are resolved (via `model-apply`) or the day rolls over.
#
# Design mirrors dotfiles-motd.fish:
#   - Instant: one jq call, no network, no gum forks (set_color only)
#   - At most once per session and once per day (state file)
#   - Silent when there's nothing pending

function __model_motd_show
    set -l ref ~/.config/opencode/model-catalog.json
    test -f "$ref"; or return 1

    set -l count (jq -r '.proposed // {} | length' "$ref" 2>/dev/null)
    test "$count" -gt 0 2>/dev/null; or return 1

    # at most once per day (and once per session)
    set -q __model_motd_shown; and return 1
    set -l state_dir ~/.local/state/dotfiles
    set -l state_file "$state_dir/model-catalog-motd"
    mkdir -p "$state_dir"
    if test -f "$state_file"; and test (cat "$state_file") = (date +%Y-%m-%d)
        return 1
    end
    date +%Y-%m-%d > "$state_file"
    set -g __model_motd_shown 1

    # "<tier> <short-name>" per proposal, up to three, then "and N more"
    set -l names (jq -r '
        .proposed // {} | to_entries | .[:3] |
        map("\(.key | split("/")[1]) (\(.value.tier))") | join(", ")' "$ref" 2>/dev/null)
    test -n "$names"; or set names "$count pending"
    test "$count" -gt 3; and set names "$names and "(math $count - 3)" more"

    set -l plural s
    test "$count" -eq 1; and set plural ""

    set_color $p_orange
    echo -n "◆ "
    set_color normal
    echo -n "$count model pick proposal$plural: "
    set_color $p_fg
    echo -n "$names"
    set_color $p_muted
    echo -n " → "
    set_color $p_cyan
    echo -n "model-apply"
    set_color normal
    echo
    return 0
end

if status --is-interactive
    __model_motd_show
end
