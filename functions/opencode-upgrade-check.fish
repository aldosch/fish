function opencode-upgrade-check --description 'Gate opencode brew upgrade until its matching @opencode-ai/plugin is >2 days old (respects min-release-age)'
    # opencode's background installer tries to resolve @opencode-ai/plugin at the
    # exact CLI version. If that plugin version is younger than the pnpm
    # min-release-age (2 days), the install fails and wastes ~1.5s per launch
    # (35s on cold cache). This gate pins opencode in brew until the matching
    # plugin has aged past the threshold, so brew upgrade skips it.
    #
    # Called by nixx before `brew upgrade`. Safe to run standalone.
    # Non-blocking: returns 0 regardless (pinning is advisory).

    set -l min_age_days 2
    set -l pkg "opencode"

    _aldo_dracula_apply_palette

    # --- is opencode installed? ---
    if not brew list --formula -q 2>/dev/null | grep -qx -- $pkg
        return 0
    end

    # --- is there an update available? ---
    set -l outdated (brew outdated --verbose $pkg 2>/dev/null)
    if test -z "$outdated"
        # already at latest — unpin if pinned (stale pin from a previous gate)
        if brew list --pinned 2>/dev/null | grep -qx -- $pkg
            brew unpin $pkg 2>/dev/null
        end
        return 0
    end

    # --- extract target version from `brew outdated --verbose` ---
    # output: "opencode (1.18.21) != 1.18.22"
    set -l target_ver (echo $outdated | string match -r '\(.*\) != (.*)' | tail -1)
    if test -z "$target_ver"
        return 0
    end

    # --- query npm for that plugin version's publish date ---
    # --registry bypasses the Socket Firewall registry in ~/.npmrc (which may
    # not index this package). time --json + jq because dot-path query breaks
    # on version numbers containing dots (time.1.18.23 is ambiguous).
    set -l npm_time (npm view @opencode-ai/plugin time --json --registry https://registry.npmjs.org/ 2>/dev/null \
        | jq -r --arg v "$target_ver" '.[$v] // empty')
    if test -z "$npm_time"
        # version doesn't exist on npm yet — can't upgrade safely, pin
        brew pin $pkg 2>/dev/null
        gum style --foreground $p_yellow "  ⏳ opencode $target_ver: plugin not on npm yet, pinned"
        return 0
    end

    # --- calculate age in days ---
    set -l age_days (python3 -c "
from datetime import datetime, timezone
pub = datetime.fromisoformat('$npm_time'.replace('Z','+00:00'))
now = datetime.now(timezone.utc)
print(f'{(now - pub).total_seconds() / 86400:.1f}')
" 2>/dev/null)

    if test -z "$age_days"
        return 0
    end

    if test (math "floor($age_days)") -ge $min_age_days
        # plugin is aged enough — allow upgrade
        brew unpin $pkg 2>/dev/null
        gum style --foreground $p_muted "  ✓ opencode $target_ver: plugin $age_days days old, upgrade allowed"
    else
        # plugin too new — pin to skip this brew upgrade cycle
        brew pin $pkg 2>/dev/null
        set -l wait (math "$min_age_days - floor($age_days)")
        gum style --foreground $p_yellow "  ⏳ opencode $target_ver: plugin only $age_days days old (need $min_age_days), pinned — retry in ~$wait day(s)"
    end
end
