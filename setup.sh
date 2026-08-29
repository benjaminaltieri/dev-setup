#!/usr/bin/env bash
# Dev setup script for MacBook Pro M4 (Apple Silicon)
# Updated for zsh (macOS default) and UV (replaces pyenv)

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "=== M4 MacBook Pro Development Setup ==="
echo "This script will set up your development environment."
echo ""

# Detect architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    BREW_PREFIX="/opt/homebrew"
    echo "Detected Apple Silicon (M4) - using $BREW_PREFIX"
else
    BREW_PREFIX="/usr/local"
    echo "Detected Intel - using $BREW_PREFIX"
fi

# Homebrew setup
if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    xcode-select --install 2>/dev/null || true
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$($BREW_PREFIX/bin/brew shellenv)"
fi

# Update brew and install base bundle
echo "Installing Homebrew packages..."
brew update
brew bundle install --file="$SCRIPT_DIR/Brewfile"

# iTerm2 Configuration
echo "Configuring iTerm2..."
ITERM2_PREF_DIR=$SCRIPT_DIR
defaults write com.googlecode.iterm2.plist PrefsCustomFolder -string "$ITERM2_PREF_DIR"
defaults write com.googlecode.iterm2.plist LoadPrefsFromCustomFolder -bool true

# Start home folder modifications
pushd ~ > /dev/null

# Copy git configuration
echo "Setting up git configuration..."
cp "$SCRIPT_DIR/.gitconfig" .
cp "$SCRIPT_DIR/.gitignore_global" .

# Fix credential helper path for Apple Silicon
if [[ "$ARCH" == "arm64" ]]; then
    echo "Updating .gitconfig credential helper paths for Apple Silicon..."
    sed -i '' 's|/usr/local/bin/gh|/opt/homebrew/bin/gh|g' ~/.gitconfig
fi

# Setup zsh (macOS default shell since Catalina)
echo "Setting up zsh configuration..."
ZSHRC=~/.zshrc

# Backup existing .zshrc if present
if [[ -f "$ZSHRC" ]]; then
    cp "$ZSHRC" "$ZSHRC.backup.$(date +%Y%m%d_%H%M%S)"
    echo "Backed up existing .zshrc"
fi

# Copy our zsh configuration
cp "$SCRIPT_DIR/.zshrc" "$ZSHRC"
chmod 700 "$ZSHRC"

# Install Rust
if ! command -v rustc >/dev/null 2>&1; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

# Install UV (Python version management - replaces pyenv)
if ! command -v uv >/dev/null 2>&1; then
    echo "Installing UV..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# Install NVM (Node Version Manager)
if [[ ! -d "$HOME/.nvm" ]]; then
    echo "Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi

# Install Claude Code
if ! command -v claude >/dev/null 2>&1 && [[ ! -f "$HOME/.claude/local/claude" ]]; then
    echo "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
    # Localize Claude Code to ~/.claude/local for faster startup
    echo "Localizing Claude Code..."
    claude migrate-installer
fi

# Go directory setup
echo "Setting up Go environment..."
mkdir -p ~/go

# Setup dotvim
echo "Setting up vim configuration..."
DOTVIM=~/.vim
if [[ -d $DOTVIM ]]; then
    echo "Updating existing vim configuration..."
    pushd $DOTVIM > /dev/null
    git pull origin master || true
    ./setup.sh
    popd > /dev/null
else
    git clone https://github.com/benjaminaltieri/dotvim $DOTVIM
    pushd $DOTVIM > /dev/null
    ./setup.sh
    popd > /dev/null
fi

# Setup Claude Code configuration
echo "Setting up Claude Code configuration..."
CLAUDE_DIR=~/.claude
mkdir -p "$CLAUDE_DIR"

if [[ -f "$SCRIPT_DIR/claude/CLAUDE.md" ]]; then
    cp "$SCRIPT_DIR/claude/CLAUDE.md" "$CLAUDE_DIR/"
    echo "Copied CLAUDE.md"
fi

if [[ -f "$SCRIPT_DIR/claude/settings.json" ]]; then
    # Merge settings if file exists, otherwise just copy
    if [[ -f "$CLAUDE_DIR/settings.json" ]]; then
        echo "Claude settings.json already exists - not overwriting"
        echo "Review $SCRIPT_DIR/claude/settings.json for any new settings to add"
    else
        cp "$SCRIPT_DIR/claude/settings.json" "$CLAUDE_DIR/"
        echo "Copied settings.json"
    fi
fi

# tmux session persistence + Claude Code session launchers
if [[ -x "$SCRIPT_DIR/tmux-sessions/install.sh" ]]; then
    echo "Installing tmux session tooling..."
    "$SCRIPT_DIR/tmux-sessions/install.sh"
fi

# End home folder modifications
popd > /dev/null

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Post-setup steps:"
echo "1. Restart your terminal or run: source ~/.zshrc"
echo "2. Configure gcloud: gcloud auth login && gcloud auth application-default login"
echo "3. Configure gh: gh auth login"
echo "4. Install Python version with UV: uv python install 3.12"
echo "5. Install Node version with NVM: nvm install --lts"
echo ""
