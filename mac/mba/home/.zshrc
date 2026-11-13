alias py='python3.11'

. "$HOME/.local/bin/env"
export PATH="$HOME/.local/bin:$PATH"
alias env='source ./venv/bin/activate'

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/h/.lmstudio/bin"
# End of LM Studio CLI section

alias srt-channel="python3 ~/Code/bin/srt-channel.py"
alias transcribe='py ~/Code/bin/transcribe'

fpath+=~/.zfunc; autoload -Uz compinit; compinit

zstyle ':completion:*' menu select
alias cc='claude --dangerously-skip-permissions'
alias ct='caffeinate -is claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official --continue'

# YouTube subtitle tools
eval "$(fnm env --use-on-cd)"

# YouTube subtitle tools

# YouTube subtitle tools

# TSOL scraper
alias tsol="py /Users/h/Code/tsol/tsol.py"

# YouTube subtitle tools
alias srt='noglob /Users/h/Code/srt/srt'
alias docling-ni='docling --image-export-mode="placeholder"'
alias pdf='py /Users/h/Code/pdfclean/pdfclean.py'

# PathMBA scrapers
alias updateArticles='cd ~/Code/pathmba-ingest && uv run python scrapers/articles.py --latest'
alias updateBooks='cd ~/Code/pathmba-ingest && uv run python scrapers/books.py --latest'

# Added by Antigravity
export PATH="/Users/h/.antigravity/antigravity/bin:$PATH"
export OPENROUTER_API_KEY="<redacted>"
export OPENROUTER_API_KEY="<redacted>"
export OPENROUTER_API_KEY="<redacted>"

# opencode
export PATH=/Users/h/.opencode/bin:$PATH

# Bounce Telegram MCP server (Claude Code auto-respawns stdio MCPs)
alias telegram-reconnect='pkill -f "bun.*telegram.*start" && echo "Telegram MCP bounced — Claude Code will respawn it"'
export GIT_TERMINAL_PROMPT=0

# Added by Antigravity IDE
export PATH="/Users/h/.antigravity-ide/antigravity-ide/bin:$PATH"
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
export SENDGRID_API_KEY="<redacted>"
alias ff="node /Users/h/Code/fontfetch/ff.mjs"
alias ff="node /Users/h/Code/fontfetch/ff.mjs"
alias ff="node /Users/h/Code/fontfetch/ff.mjs"
alias store='npm --prefix /Users/h/Code/hbsp-tui run store'
# Dictated commands arrive capitalised and with a full stop: "Grid." runs grid
alias Grid=grid Grid.=grid grid.=grid
