function _oc_start_portal --description 'Start openportal in a detached screen session'
    set -l name "portal-"(basename (pwd))
    openportal stop 2>/dev/null
    screen -dmsm $name fish -c 'openportal --hostname 0.0.0.0'
    sleep 3
    openportal list
end
