# 🐟 fish

aldo's fish shell config.

![example screenshot](/screenshot.png)

## layout

- `config.fish` — aliases, env vars, path setup, tool init (starship, fnm, direnv)
- `conf.d/` — sourced automatically on every shell start
  - `aldo-dracula-palette.fish` — adaptive dracula/alucard colours that follow the macos dark/light setting
  - `fish_frozen_theme.fish`, `fish_frozen_key_bindings.fish` — fish 4.3 migration files
  - `fnm.fish` — node version manager hook
- `functions/` — one function per file (see below)
- `fish_variables` — universal variables

## functions

### shortcuts

- `e [path]` — open nvim (current dir if no arg)
- `c [path]` — open the editor
- `o [path]` — open finder
- `t [path]` — open typora
- `typora [path]` — same, explicit

### git

- `git-status-pretty` (aliased `gs`) — coloured, grouped status
- `ga [path]` — add, then show status + diff
- `gc [msg]` — commit (opens editor if no msg)
- `gcp [msg]` — commit and push
- `git` — wraps `git clone`: rewrites github https urls to ssh and falls back to https if that fails
- `ggs [dir]` — global status across every repo in a directory (default `~/dev`)
- `pullall [dir]` — fast-forward every tracked branch across repos, ordered by recent activity (default `~/dev`)

### system

- `nixx` — nix-darwin update/build/apply wrapper with drift checking. see the [nix repo](https://github.com/aldosch/nix)
- `nixx-drift` — reports packages installed but not declared (and vice versa) across brew, pnpm and uv
- `skills-restore` — reinstall agent skills from a lockfile

### media

- `yoink <url>` (aliased `grab`) — download a site as llm-ready markdown plus its binary assets
- `video-context <file>` — pull a transcript (whisper) and screenshots out of a video for feeding to an llm
- `fix-audio <file>` — collapse a one-sided recording to dual mono and loudness-normalise it
- `normalise-audio <file>` — loudness-normalise audio, keep the video stream
- `watch-unzip <dir>` — watch a folder and auto-extract zips as they land

### text & files

- `bat` — bat with a theme that follows dark/light mode
- `fif <string>` — fuzzy find inside files (ripgrep + fzf)
- `pjson` — format every json file in the current dir
- `proofread` — proofread clipboard text with a local ollama model
- `hear` — text-to-speech via elevenlabs

### prompt

- `fish_prompt`, `fish_right_prompt` — the prompt itself (ssh host, pwd, git state)

## install

clone into `~/.config/fish`:

```bash
git clone git@github.com:aldosch/fish.git ~/.config/fish
```

some functions expect tools that live in the [nix](https://github.com/aldosch/nix) config (gum, eza, ripgrep, fzf, etc.).
</content>
