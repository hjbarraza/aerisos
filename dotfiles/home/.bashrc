#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# --- Terminal tools (Omarchy-style) ---
export EDITOR=nvim
alias ls='eza --icons=auto --group-directories-first'
alias ll='eza -l --icons=auto --group-directories-first --git'
alias la='eza -la --icons=auto --group-directories-first --git'
alias tree='eza --tree --icons=auto'
alias cat='bat --paging=never --style=plain'
alias lg='lazygit'
eval "$(fzf --bash)"        # Ctrl+R history search, Ctrl+T file search, Alt+C cd
eval "$(zoxide init bash)"  # z <part of folder name> to jump
eval "$(starship init bash)"

# --- AerisOS greeting: new kitty/ghostty windows only (not tmux, neovim's terminal or scripts) ---
# Ghostty is detected via GHOSTTY_RESOURCES_DIR since our config overrides TERM to xterm-256color.
[[ ( $TERM == xterm-kitty || -n $GHOSTTY_RESOURCES_DIR ) && -z $TMUX && -z $NVIM && -x ~/.local/bin/aeris-greeting ]] && ~/.local/bin/aeris-greeting

# opencode
export PATH=/home/h/.opencode/bin:$PATH
export PATH="$HOME/.local/bin:$PATH"
