#!/usr/bin/env bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# brew setup
if ! command -v brew >/dev/null 2>&1; then
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
git -C "$(brew --repo homebrew/core)" fetch --unshallow
fi

# update brew and install base bundle
brew update
brew bundle install

# don't forget to configure gdb
# https://sourceware.org/gdb/wiki/PermissionsDarwin

# iTerm2 Configuration - NEEDS TESTING MAY NOT WORK
ITERM2_PREF_DIR=$SCRIPT_DIR
# Specify the preferences directory
defaults write com.googlecode.iterm2.plist PrefsCustomFolder -string "$ITERM2_PREF_DIR"
# Tell iTerm2 to use the custom preferences in the directory
defaults write com.googlecode.iterm2.plist LoadPrefsFromCustomFolder -bool true

# start home folder modifications
pushd ~
cp $SCRIPT_DIR/.gitconfig .
cp $SCRIPT_DIR/.gitignore_global .

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

# git bash completion
curl https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash -o /usr/local/etc/git_completion
echo '[ -f /usr/local/etc/git_completion ] && . /usr/local/etc/git_completion' >> $BASHRC

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
# source changes and test
source $BASH_PROFILE
virtualenvwrapper

# save all bash history
cat >> $BASHRC <<'codeblock'
# Eternal bash history.
# ---------------------
# Undocumented feature which sets the size to "unlimited".
# http://stackoverflow.com/questions/9457233/unlimited-bash-history
export HISTFILESIZE=9999999999
export HISTSIZE=9999999999
export HISTTIMEFORMAT="[%F %T] "
# Change the file location because certain bash sessions truncate .bash_history file upon close.
# http://superuser.com/questions/575479/bash-history-truncated-to-500-lines-on-each-login
export HISTFILE=~/.bash_eternal_history
# Force prompt to write history after every command.
# http://superuser.com/questions/20900/bash-history-loss
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
codeblock

# install rust
curl https://sh.rustup.rs -sSf | sh -s -- -y

# pyenv setup
cat >> $BASHRC <<'codeblock'
export PATH="$HOME/.pyenv/shims:$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
codeblock
source $BASH_PROFILE
pyenv install 3.9.9
pyenv global 3.9.9

# poetry setup
curl -sSL https://install.python-poetry.org | python3 -
echo 'export PATH="$HOME/.poetry/bin:$PATH"' >> $BASHRC

# using minikube for docker daemon
cat >> $BASHRC <<'codeblock'
# start minikube if it isn't already running (login shell only)
if shopt -q login_shell && ! minikube status >/dev/null 2>&1; then
minikube start
fi
# configure docker to use minikube
eval $(minikube docker-env)
codeblock

# GDB config stuff for macOS
echo "set startup-with-shell off" >> ~/.gdbinit

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
