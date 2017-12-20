#!/usr/bin/env bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# brew setup
if ! command -v brew >/dev/null 2>&1; then
xcode-select --install
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
git -C "$(brew --repo homebrew/core)" fetch --unshallow
fi

# regular brew installs
brew install python byobu ctags

# cask installs
brew cask install iterm2 macdown

# start home folder modifications
pushd ~
cp $SCRIPT_DIR/.gitconfig .

# special for python, add the homebrew version into path
if ! [ -f .bash_profile ]; then
    touch .bash_profile
fi
echo 'export PATH="/usr/local/opt/python/libexec/bin:$PATH"' >> .bash_profile

# setup dotvim
if [ -d .vim ]; then
    rm -rf .vim
fi
git clone https://github.com/benjaminaltieri/dotvim .vim
pushd .vim
./setup.sh
popd

# end home folder modifications
popd
