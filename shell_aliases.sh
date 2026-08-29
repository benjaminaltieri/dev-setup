#!/bin/bash
# Portable shell aliases - works in both bash and zsh
# Source this file from your .bashrc or .zshrc

# Kubernetes aliases
alias ktl=kubectl
alias ktx=kubectx

# Google Cloud aliases
alias gcd=gcloud
alias gcfg="gcloud config set"
alias gctx="gcloud config configurations activate"
alias gauth="gcloud auth login"
alias gadc="gcloud auth login --update-adc"

# GitHub CLI aliases
alias ghpr="gh pr create"
alias ghprd="gh pr create --draft"

# Terraform aliases
alias tf="terraform"
alias tfi="terraform init"
alias tfws="terraform workspace select"
alias tfp="terraform plan -lock=false"

# General utilities
alias ls="ls -lah"
alias lt="tree"

# QS-specific pip install with private PyPI
alias qspi="pip install --extra-index-url https://us-central1-python.pkg.dev/qs-infrastructure-002/qs-python/simple/ --index-url https://pypi.org/simple/"

# tree_aligned function - pretty tree output with aligned metadata
# Works in both bash and zsh
tree_aligned() {
    tree -L 3 -n -gulpahDU --du "$@" | sed -E 's/^(.*[│├└─ ])(\[.+\]) +(.+)$/\1\3###\2/' | awk -F'###' '{
        if (NF == 2) {
            gsub(/^\[/, "[ ", $2)
            pad_len = 68 - length($1)
            if (pad_len < 2) pad_len = 2
            printf "%s%" pad_len "s%s\n", $1, "", $2
        } else {
            print $0
        }
    }'
}
alias treel='tree_aligned'


# Claude Code aliases
alias claude="$HOME/.local/bin/claude"
alias clod="claude --dangerously-skip-permissions"
alias clodcon="claude --dangerously-skip-permissions --continue"
alias clodres="claude --dangerously-skip-permissions --resume"
alias clodfork="claude --dangerously-skip-permissions --fork-session --resume"
alias clad="claude --enable-auto-mode"
alias cladcon="claude --enable-auto-mode --continue"
alias cladres="claude --enable-auto-mode --resume"
# cld*: no explicit permission flag, so permissions.defaultMode in
# ~/.claude/settings.json decides (currently "auto").
alias cld="claude"
alias cldcon="claude --continue"
alias cldres="claude --resume"
alias cldfork="claude --fork-session --resume"
