function exc-restore --description 'Restore scene content from an exc-snap snapshot json (PUT full replace). Usage: exc-restore <snapshot.json>'
    if test (count $argv) -ne 1
        echo "Usage: exc-restore <snapshot.json>" >&2
        return 1
    end
    set -l file $argv[1]
    if not test -f $file
        echo "exc-restore: no such file: $file" >&2
        return 1
    end
    set -l scene_id (jq -r '.scene.metadata.id // .scene.id // empty' $file)
    set -l scene_name (jq -r '.scene.metadata.name // .scene.name // "unknown"' $file)
    set -l ts (jq -r '.snapshotted_at // "unknown"' $file)
    if test -z "$scene_id"
        echo "exc-restore: snapshot has no scene id" >&2
        return 1
    end
    echo "Restoring snapshot from $ts into scene \"$scene_name\" ($scene_id)"
    echo "This REPLACES the current content of that scene."
    read -l -P "Type y to confirm: " answer
    if test "$answer" != y
        echo "exc-restore: aborted"
        return 1
    end
    set -l payload (jq -c '.content' $file)
    _exc_api PUT "/scenes/$scene_id/content" "$payload"
    or return 1
    echo "exc-restore: restored $file -> scene $scene_id"
end
