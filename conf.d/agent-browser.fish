# agent-browser dashboard: always reachable through portless
# (https://dashboard.agent-browser.localhost alias -> port 4848).
# Setting this globally means every `agent-browser dashboard start`
# (explicit or implicit) accepts the portless origin, so repeated
# starts reuse the same single instance instead of restarting it.
set -gx AGENT_BROWSER_DASHBOARD_ALLOWED_ORIGINS https://dashboard.agent-browser.localhost
