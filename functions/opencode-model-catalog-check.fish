# opencode-model-catalog-check - render pending model-catalog proposals
#
# Offline and instant: reads opencode/model-catalog.json and prints the
# proposals the background research pipeline has filed (plus a staleness
# hint). All the network work — fetching the live gateway catalog,
# triaging new models, researching compelling ones — happens in the daily
# maintenance task (scripts/maintenance/model-catalog-sync.sh) so this
# surface never slows `nixx check` down. Apply proposals with `model-apply`.
#
# Called automatically as surface 5 of `nixx check` / `nixx d`. Safe to run
# standalone any time.

function opencode-model-catalog-check
    python3 ~/.config/fish/scripts/opencode-model-catalog-check.py
end
