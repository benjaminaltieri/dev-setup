#!/usr/bin/env bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# brew setup
if ! command -v brew >/dev/null 2>&1; then
xcode-select --install
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
git -C "$(brew --repo homebrew/core)" fetch --unshallow
fi

# regular brew installs
brew install python byobu ctags wget

# cask installs
brew cask install iterm2 macdown

# start home folder modifications
pushd ~
cp $SCRIPT_DIR/.gitconfig .

# let's create our bash dot files and route correctly
BASH_PROFILE=~/.bash_profile
BASHRC=~/.bashrc
if ! [ -f $BASH_PROFILE ]; then
    touch $BASH_PROFILE
    chmod 700 $BASH_PROFILE
fi
echo "[ -r $BASHRC ] && . $BASHRC" >> $BASH_PROFILE
if ! [ -f $BASHRC ]; then
    touch $BASHRC
    chmod 700 $BASHRC
fi
# special for python, add the homebrew version into path
echo 'export PATH="/usr/local/opt/python/libexec/bin:$PATH"' >> $BASHRC
# test it
source $BASHRC
BREW_PYTHON="$(command -v python)"
echo $BREW_PYTHON
python --version

# installs via pip
pip install virtualenv virtualenvwrapper
VIRTUALENV_BIN="$(command -v virtualenv)"
echo $VIRTUALENV_BIN

# virtualenvwrapper requires some more setup
# courtesy of http://mkelsey.com/2013/04/30/how-i-setup-virtualenv-and-virtualenvwrapper-on-my-mac/
cat >> $BASHRC <<'codeblock'
# set where virtual environments will live
export WORKON_HOME=$HOME/.virtualenvs
# we have a special install, so set these as well
export VIRTUALENVWRAPPER_PYTHON="$(command -v python)"
export VIRTUALENVWRAPPER_VIRTUALENV="$(command -v virtualenv)"
# ensure all new environments are isolated from the site-packages directory
export VIRTUALENVWRAPPER_VIRTUALENV_ARGS='--no-site-packages'
# use the same directory for virtualenvs as virtualenvwrapper
export PIP_VIRTUALENV_BASE=$WORKON_HOME
# makes pip detect an active virtualenv and install to it
export PIP_RESPECT_VIRTUALENV=true
if [[ -r /usr/local/bin/virtualenvwrapper.sh ]]; then
	source /usr/local/bin/virtualenvwrapper.sh
else
	echo "WARNING: Can't find virtualenvwrapper.sh"
fi
codeblock
source $BASH_PROFILE
virtualenvwrapper

# setup dotvim
DOTVIM=~/.vim
if [ -d $DOTVIM ]; then
    rm -rf $DOTVIM
fi
git clone https://github.com/benjaminaltieri/dotvim $DOTVIM
pushd $DOTVIM
./setup.sh
popd

# end home folder modifications
popd
