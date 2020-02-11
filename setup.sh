#!/usr/bin/env bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# apt installs
sudo apt-get update
sudo apt-get install -y \
	build-essential \
	byobu \
	cmake \
	exuberant-ctags \
	git \
	python-pip \
	python3-pip \
	vim \
	virtualenv \


# snappy installs
snap install hub --classic

# install rustup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# start home folder modifications
pushd ~
cp $SCRIPT_DIR/.gitconfig .

# let's create our bash dot files and route correctly
PROFILE=~/.profile
BASHRC=~/.bashrc
if ! [ -f $PROFILE ]; then
    touch $PROFILE
    chmod 700 $PROFILE
    echo "[ -r $BASHRC ] && . $BASHRC" >> $PROFILE
fi
if ! [ -f $BASHRC ]; then
    touch $BASHRC
    chmod 700 $BASHRC
fi

# special for python pip bin installs
echo 'export PATH="$HOME/.local/bin:$PATH"' >> $BASHRC
source $BASHRC

# installs via pip3
pip3 --version
pip3 install virtualenv virtualenvwrapper

# virtualenvwrapper requires some more setup
# courtesy of http://mkelsey.com/2013/04/30/how-i-setup-virtualenv-and-virtualenvwrapper-on-my-mac/
cat >> $BASHRC <<'codeblock'
# set where virtual environments will live
export WORKON_HOME=$HOME/.virtualenvs
# we have a special install, so set these as well
export VIRTUALENVWRAPPER_PYTHON="$(command -v python3)"
export VIRTUALENVWRAPPER_VIRTUALENV="$(command -v virtualenv)"
# ensure all new environments are isolated from the site-packages directory
export VIRTUALENVWRAPPER_VIRTUALENV_ARGS='--no-site-packages'
# use the same directory for virtualenvs as virtualenvwrapper
export PIP_VIRTUALENV_BASE=$WORKON_HOME
# makes pip detect an active virtualenv and install to it
export PIP_RESPECT_VIRTUALENV=true
if [[ -r ~/.local/bin/virtualenvwrapper.sh ]]; then
	source ~/.local/bin/virtualenvwrapper.sh
else
	echo "WARNING: Can't find virtualenvwrapper.sh"
fi
codeblock

# save all bash history
cat >> $BASHRC <<'codeblock'
# Eternal bash history.
# ---------------------
# Undocumented feature which sets the size to "unlimited".
# http://stackoverflow.com/questions/9457233/unlimited-bash-history
export HISTFILESIZE=-1
export HISTSIZE=-1
export HISTTIMEFORMAT="[%F %T] "
# Change the file location because certain bash sessions truncate .bash_history file upon close.
# http://superuser.com/questions/575479/bash-history-truncated-to-500-lines-on-each-login
export HISTFILE=~/.bash_eternal_history
# Force prompt to write history after every command.
# http://superuser.com/questions/20900/bash-history-loss
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
codeblock

# check bashrc forwarding
source $PROFILE
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
