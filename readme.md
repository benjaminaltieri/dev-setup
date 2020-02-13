# Ben's Linux Development Environment
Targeting Ubuntu Bionic 18.04

## Downloads
These will be installed from downloads:

Chrome: [https://www.google.com/chrome/browser/]()

### Aptitude Installs:

These can be installed with `sudo apt-get install`:

* `build-essential` - essential build tools
* `byobu` - terminal mux front end for tmux/screen
* `cmake` - build script generation
* `exuberant-ctags` - source tagging
* `git` - the git version control tool
* `gnome-tweak-tool` - used to map caps lock to esc
* `vim` - vi improved

### Snappy Installs:

These can be installed with `snap install`:

* `hub` - unofficial github cli

### Remap caps lock to escape
From [this](https://askubuntu.com/questions/1059663/remapping-caps-lock-to-escape-in-ubuntu-18-04-bionic) post:
Gnome Tweaks -> Keyboard & Mouse -> Additional Layout Options -> Caps Lock key behavior.

### Install rustup
```curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh```

## VIM Setup
My dotvim configuration can be cloned from github. The procedure is as follows:

```bash
$ rm -rf ~/.vim
$ git clone https://github.com/benjaminaltieri/dotvim ~/.vim
$ cd ~/.vim
$ ./setup.sh
```

## Python
Python is installed by default in Linux but we need some other tools to make our python world a bit easier:

### Virtualenv and virtualenvwrapper
To manage per repository python package dependencies we use `virtualenv`, which is pip installable:

```bash
$ pip3 install virtualenv virtualenvwrapper
```

Then in order to activate the wrapper, add these lines to your  `.bash_profile` or `.bashrc`:

```bash
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
```

[Ref](http://mkelsey.com/2013/04/30/how-i-setup-virtualenv-and-virtualenvwrapper-on-my-mac/)

### Git Aliases
* `pn` - push the current branch with the -u option to set up tracking (stands for 'push new')
* `au` - add previously tracked files to index (add -u)
* `bdel` - delete branch locally and remotely (as long as they share the same name)

