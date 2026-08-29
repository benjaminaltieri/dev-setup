# M4 MacBook Pro Migration Guide

## Prerequisites

Before running setup, ensure you have:
1. Signed into iCloud and App Store
2. Installed Xcode from the App Store (or at minimum, accepted the Xcode license)

## Quick Start

```bash
# Clone this repo
git clone https://github.com/benjaminaltieri/dev-setup ~/misc/dev-setup
cd ~/misc/dev-setup

# Checkout the M4 migration branch
git checkout benaltieri/qsb-m4-migration

# Run setup
./setup.sh
```

## What Gets Installed

### Package Managers & Tools
- **Homebrew** - Package manager for macOS
- **UV** - Python version and package management (replaces pyenv)
- **NVM** - Node version management
- **Rust** - Via rustup

### Development Tools (via Homebrew)
- vim, emacs, tmux, byobu
- git, gh (GitHub CLI)
- docker, docker-compose
- kubectl, kubectx, k9s
- terraform (via `tf` alias)
- ripgrep, jq, tree, watch, wget
- direnv, terminal-notifier

### Cloud & Database
- Google Cloud SDK
- DBeaver Community
- cypher-shell

### Applications (Casks)
- iTerm2
- Visual Studio Code
- MacDown

### AI Tools
- Claude Code (with localization for faster startup)

## Post-Setup Steps

After `setup.sh` completes, restart your terminal and run:

### 1. Authenticate with Google Cloud
```bash
gcloud auth login
gcloud auth application-default login
```

### 2. Authenticate with GitHub
```bash
gh auth login
```

### 3. Install Python
```bash
uv python install 3.12
# Or whatever version you need
```

### 4. Install Node.js
```bash
nvm install --lts
```

### 5. Configure Claude Code
```bash
# First run will prompt for API key or Anthropic account login
claude
```

## Manual Steps (Not Automated)

### SSH Keys
Copy your SSH keys from your old machine or generate new ones:
```bash
# Generate new key
ssh-keygen -t ed25519 -C "benaltieri@gmail.com"

# Add to ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Copy public key to clipboard and add to GitHub
pbcopy < ~/.ssh/id_ed25519.pub
```

### GPG Keys (if using signed commits)
Export from old machine and import on new one, or generate new keys.

### Application-Specific Settings
- **Docker Desktop**: Install separately from docker.com if needed
- **1Password / Password Manager**: Install and configure
- **Slack, Zoom, etc.**: Install from App Store or download

## File Locations

| File | Purpose |
|------|---------|
| `~/.zshrc` | Shell configuration |
| `~/.gitconfig` | Git configuration |
| `~/.gitignore_global` | Global gitignore |
| `~/.claude/CLAUDE.md` | Claude Code instructions |
| `~/.claude/settings.json` | Claude Code settings |
| `~/.vim/` | Vim configuration (cloned from dotvim repo) |

## Key Aliases

### Git (see .gitconfig for full list)
- `git cob <name>` - Create branch with `benaltieri/` prefix
- `git comp` - Checkout main and pull
- `git prom` - Pull rebase origin main
- `git au` - Add all tracked files
- `git c` - Commit with verbose diff
- `git pf` - Push force-with-lease

### Shell (see shell_aliases.sh)
- `ktl` - kubectl
- `ktx` - kubectx
- `tf` - terraform
- `gcd` - gcloud
- `ghpr` - gh pr create

## Troubleshooting

### Homebrew permissions issues
```bash
sudo chown -R $(whoami) /opt/homebrew
```

### NVM not found after install
Restart your terminal or run:
```bash
source ~/.zshrc
```

### Claude Code not found
The alias points to the localized version. If localization failed:
```bash
# Try running the global version
npx @anthropic-ai/claude-code

# Or re-localize
claude /localize
```

### Git credential helper issues
Ensure gh is authenticated first:
```bash
gh auth login
gh auth status
```
