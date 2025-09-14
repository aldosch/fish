# ------------------------------
# ALIASES
# ------------------------------

# Git aliases
alias gs="git-status-pretty"
alias gd="git diff --cached"
alias gp="git push"

# Screen aliases
alias sl="screen -ls | awk '/\t/ {print \$1}' | sed 's/^[0-9]*\.//'"
alias sr="screen -r"
alias ss="screen -S"

# Config editing aliases
alias zr="source ~/.config/fish/config.fish"
alias zz="nvim ~/.config/fish/config.fish && source ~/.config/fish/config.fish"

# GitHub Copilot aliases
alias ee="gh copilot explain"
alias explain="gh copilot explain"
alias ss="gh copilot suggest"
alias suggest="gh copilot suggest"

# Power management
alias coffee="sudo pmset -b disablesleep 1"
alias tea="sudo pmset -b disablesleep 0"

# Utility aliases
alias aii="cd ~/.config/aichat"
alias cat="bat -pp"
alias comm="vercel_community"
alias dl3="yt-dlp -x --audio-format mp3 --audio-quality 0 --output '%(channel)s - %(title)s.%(ext)s'"
alias p3="python3"
alias pb="pbcopy"
alias pjson="prettier *.json --write"
alias rain="onsen | ~/dot/rain/rain"
alias stack="stacks-cli"
alias thb="bun ~/dev/thb/index.ts"
alias vcase="vercel-case"
alias vv="vercel-case"
alias zed="open -a /Applications/Nix\ Apps/Zed.app -n"

# ------------------------------
# ENVIRONMENT VARIABLES
# ------------------------------

set -x BAT_THEME Dracula
set -x BUN_INSTALL "$HOME/.bun"
set -x CLAUDE_CONFIG_DIR "$HOME/.config/claude"
set -x ELEVEN_API_KEY "op://Private/eleven labs/API key 2025-04-15<D-g>"
set -x V0_API_KEY "op://Private/v0 API streaming test/password"

# ------------------------------
# PATH CONFIGURATION
# ------------------------------

# Add Bun to path
set -x PATH "$BUN_INSTALL/bin" $PATH

# Add fnm path
set -x PATH "/Users/aldo/Library/Application Support/fnm" $PATH

# pnpm configuration
set -gx PNPM_HOME /Users/aldo/Library/pnpm
if not string match -q -- $PNPM_HOME $PATH
    set -gx PATH "$PNPM_HOME" $PATH
end

# pipx binaries
set PATH $PATH /Users/aldo/.local/bin

# ------------------------------
# TOOL INITIALIZATIONS
# ------------------------------

# Initialize starship prompt
starship init fish | source

# Initialize fnm
fnm env --use-on-cd --version-file-strategy=recursive | source

# Initialize direnv and thefuck
direnv hook fish | source

# Disable fish greeting
set fish_greeting ""

