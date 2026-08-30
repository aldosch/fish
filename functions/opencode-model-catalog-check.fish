# opencode-model-catalog-check - check if the model tables in agent.mdx are stale
#
# Compares opencode/model-catalog.json (the reference snapshot behind the
# "powerful" and "efficient" model tables in docs/content/docs/agent.mdx)
# against the live Vercel AI Gateway catalog. Flags providers that now have a
# newer tool-use model we haven't reviewed, or a documented pick that's
# disappeared from the catalog entirely.
#
# Read-only: only calls GET /v1/models (free). Never edits files — findings
# are informational, since deciding whether a newer model is actually better
# (see: Claude Fable 5 being creative-only, not a coding upgrade) needs a
# human or an agent to look, not a mechanical swap.
#
# Called automatically as surface 6 of `nixx check` / `nixx d`. Safe to run
# standalone any time.

function opencode-model-catalog-check
    python3 ~/.config/fish/scripts/opencode-model-catalog-check.py
end
