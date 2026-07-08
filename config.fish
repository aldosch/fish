# ------------------------------
# ALIASES
# ------------------------------

alias crawl="crwl"
alias grab="yoink"

# Git aliases
alias gs="git-status-pretty"
# alias gs="git status"
alias gd="git diff --cached"
alias gp="git push"

# Screen aliases
alias sr="screen -r"
alias sl="screen -ls | awk '/\t/ {print \$1}' | sed 's/^[0-9]*\.//'"

# Config editing aliases
alias zz="nvim ~/.config/fish/config.fish && source ~/.config/fish/config.fish"
alias zr="source ~/.config/fish/config.fish"

# GitHub Copilot aliases
alias ee="gh copilot explain"
alias explain="gh copilot explain"
alias ss="gh copilot suggest"
alias suggest="gh copilot suggest"

# Power management
alias coffee="sudo pmset -b disablesleep 1"
alias tea="sudo pmset -b disablesleep 0"

# Utility aliases
alias cat="bat -pp"
alias dl3="yt-dlp -x --audio-format mp3 --audio-quality 0 --output '%(channel)s - %(title)s.%(ext)s'"
alias oc="opencode"
alias p3="python3"
alias pb="pbcopy"
alias t="typora"

alias python="python3"
alias zed="open -a /Applications/Nix\ Apps/Zed.app -n"

# ------------------------------
# ENVIRONMENT VARIABLES
# ------------------------------
#
# Secrets are loaded from the macOS Keychain at shell startup — no plaintext
# credentials live in this file. Add a secret with:
#   security add-generic-password -a "$USER" -s "MY_API_KEY" -w "the-actual-key"
# then load it below.

set -x BUN_INSTALL "$HOME/.bun"
set -x AI_GATEWAY_API_KEY (security find-generic-password -a "$USER" -s "AI_GATEWAY_API_KEY" -w)
set -x CONTEXT7_API_KEY (security find-generic-password -a "$USER" -s "CONTEXT7_API_KEY" -w)
set -x EDITOR nvim
set -x PI_CODING_AGENT_DIR "$HOME/.config/pi"

# ------------------------------
# PATH CONFIGURATION
# ------------------------------

# Add Bun to path
set -x PATH "$BUN_INSTALL/bin" $PATH

# Add Homebrew path
set -x PATH "/opt/homebrew/bin" $PATH

# Add fnm path
set -x PATH "$HOME/Library/Application Support/fnm" $PATH

# pnpm configuration
set -gx PNPM_HOME "$HOME/Library/pnpm"
if not string match -q -- $PNPM_HOME $PATH
    set -gx PATH "$PNPM_HOME" $PATH
end

# ------------------------------
# TOOL INITIALIZATIONS
# ------------------------------

# Initialize starship prompt
starship init fish | source

# Initialize fnm
fnm env --use-on-cd --version-file-strategy=recursive | source

# Initialize direnv (silent mode - only show errors)
set -x DIRENV_LOG_FORMAT ""
direnv hook fish | source

# Disable fish greeting
set fish_greeting ""

# local bin (claude code, etc.)
fish_add_path "$HOME/.local/bin"
