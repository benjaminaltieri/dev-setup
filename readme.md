#Ben's macOS Development Environment

##Downloads
These will be installed from downloads:

Chrome: [https://www.google.com/chrome/browser/]()

iTerm2: [https://www.iterm2.com/index.html]() (optionally `brew cask install iterm2` after `brew` is setup)

##Brew
To install `brew`, run the following commands (assumes xcode not installed):

```bash
$ xcode-select --install
$ /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

[Reference](https://brew.sh/)

###Brew Installs:

These can be installed with `brew install`:

* `python` - brew's version of python with is usually more recent than the default python supplied by macOS. 
* `byobu` - terminal mux front end for tmux/screen
* `ctags` - source tagging

These can be installed with `brew cask install`:

* `iterm2` - modern terminal replacement for macOS `terminal`
* `macdown` - markdown editor with realtime rendering


##VIM Setup
My dotvim configuration can be cloned from github. The procedure is as follows:

```bash
$ rm -rf ~/.vim
$ git clone https://github.com/benjaminaltieri/dotvim ~/.vim
$ cd ~/.vim
$ ./setup.sh
```

##Python
Python is installed by homebrew (or by default macOS if you chose not to install it) but we need some other tools to make our python world a bit easier:

###Virtualenv and virtualenvwrapper
To manage per repository python package dependencies we use `virtualenv`, which is pip installable:

```bash
$ pip install virtualenv virtualenvwrapper
```

Then in order to activate the wrapper, add these lines to your  `.bash_profile` or `.bashrc`:

```bash
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
```

[Ref](http://mkelsey.com/2013/04/30/how-i-setup-virtualenv-and-virtualenvwrapper-on-my-mac/)
