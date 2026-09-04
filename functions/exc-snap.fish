function exc-snap --description 'Snapshot Excalidraw+ scene(s) into ~/.config/excalidraw (git auto-commit). Usage: exc-snap <scene-id-or-name> | exc-snap --all'
    set -l repo "$HOME/.config/excalidraw"
    if test (count $argv) -ne 1
        echo "Usage: exc-snap <scene-id-or-name> | exc-snap --all" >&2
        return 1
    end
    set -l ids
    if test "$argv[1]" = --all
        set ids (_exc_scene_ids)
        or return 1
        if test (count $ids) -eq 0
            echo "exc-snap: no scenes found"
            return 0
        end
    else
        set ids (_exc_scene_ids $argv[1])
        or return 1
    end
    for id in $ids
        _exc_snap_one $id
        or set -l failed 1
    end
    if set -q failed
        echo "exc-snap: some snapshots failed; nothing committed" >&2
        return 1
    end
    git -C $repo add -A 2>/dev/null
    if git -C $repo diff --cached --quiet
        echo "exc-snap: no changes since last snapshot"
    else
        git -C $repo commit -q -m "snap "(date +%Y-%m-%dT%H-%M-%S)
        and echo "exc-snap: committed to $repo"
    end
end
