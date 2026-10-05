# model-apply - apply proposed model picks from opencode/model-catalog.json
#
# The daily maintenance model-catalog-sync task researches compelling new
# gateway models and files them under "proposed" in the catalog. This
# function applies them: show the list, one confirmation, then every
# proposal is applied (tier pick swap + agent.mdx table row +
# opencode.json gateway-routing entry), followed by an offer to commit +
# push. Passing a model id applies just that one.
#
# Surfaced by the shell motd (conf.d/model-catalog-motd.fish) whenever
# proposals are pending.

function model-apply --description 'Apply proposed model picks'
    set -l ref ~/.config/opencode/model-catalog.json
    set -l repo ~/.config

    if not test -f $ref
        echo "model-apply: no catalog at $ref"
        return 1
    end

    set -l proposals (jq -r '.proposed // {} | keys[]' $ref 2>/dev/null)
    if test (count $proposals) -eq 0
        echo "model-apply: no pending proposals"
        return 0
    end

    # which ids: an explicit argument applies just that one; default is all
    set -l ids $proposals
    if test (count $argv) -ge 1
        set ids $argv[1]
    else
        echo ""
        for id in $ids
            jq -r --arg id $id '"  " + $id + "  " + .proposed[$id].tier + "  " + .proposed[$id].why' $ref
        end
        echo ""
    end

    python3 ~/.config/fish/scripts/opencode-model-apply.py $ids; or return 1

    # offer to commit + push exactly the files the apply touched (they're
    # outside dots-autocommit's allowlist, so nothing else would)
    set -l dirty (git -C $repo status --porcelain -- \
        opencode/model-catalog.json opencode/opencode.json docs/content/docs/agent.mdx \
        | string sub --start 4 | string trim)
    if test (count $dirty) -eq 0
        return 0
    end

    if type -q gum
        gum confirm "commit + push these picks?"; or begin
            echo "model-apply: left uncommitted"
            return 0
        end
    end

    set -l shorts (string replace -r '^.*/' '' -- $ids)
    git -C $repo add -- $dirty
    and git -C $repo commit -q -m "model-apply: "(string join ', ' $shorts)" picks"
    or begin
        echo "model-apply: commit failed"
        return 1
    end

    if git -C $repo push -q origin HEAD 2>/dev/null
        echo "model-apply: committed + pushed"
    else
        git -C $repo pull --rebase -q 2>/dev/null
        if git -C $repo push -q origin HEAD 2>/dev/null
            echo "model-apply: committed + pushed (after rebase)"
        else
            echo "model-apply: committed, push failed — run git push later"
        end
    end
end
