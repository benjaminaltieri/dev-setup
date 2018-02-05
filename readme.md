# Ben's macOS Development Environment for Swift

## Downloads
These will be installed from downloads:

Chrome: [https://www.google.com/chrome/browser/]()

iTerm2: [https://www.iterm2.com/index.html]() (optionally `brew cask install iterm2` after `brew` is setup)

Docker: [https://docs.docker.com/docker-for-mac/install/#download-docker-for-mac]()

## Brew
To install `brew`, run the following commands (assumes xcode not installed):

```bash
$ xcode-select --install
$ /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

[Reference](https://brew.sh/)

### Brew Installs:

These can be installed with `brew install`:

* `python` - brew's version of python with is usually more recent than the default python supplied by macOS. 
* `byobu` - terminal mux front end for tmux/screen
* `ctags` - source tagging
* `lastpass-cli --with-pinentry --withdoc` - lastpass in the command line for use with github 2FA PAKs
* `check` - Unit testing framework for C
* `gdb --with-all-targets --with-python` - for debugging with support for ARM targets

These can be installed with `brew cask install`:

* `iterm2` - modern terminal replacement for macOS `terminal`
* `macdown` - markdown editor with realtime rendering

## Byobu Configuration for macOS and iTerm2
Following the steps referenced [here](https://stackoverflow.com/a/26470118) we can get the proper shortcut forwarding that byobu expects.

So far this is manual, maybe improve with script ([ref.](https://apple.stackexchange.com/a/115799)), but the gist is:

1. Remove built-in macOS shortcuts that use F1-F12
2. Manually edit iTerm2 profile to use linux terminal type and configure these shortcuts with the 'Send Escape Sequence' option:
	
 -  <kbd>CTRL</kbd> + <kbd>F2</kbd> : `[1;5Q`
 -  <kbd>CTRL</kbd> + <kbd>SHIFT</kbd> + <kbd>F2</kbd> : `[1;6Q`
 -  <kbd>ALT</kbd> + <kbd>LEFT</kbd> : `[1;3D`
 -  <kbd>ALT</kbd> + <kbd>RIGHT</kbd> : `[1;3C`
 -  <kbd>ALT</kbd> + <kbd>UP</kbd> : `[1;3A`
 -  <kbd>ALT</kbd> + <kbd>DOWN</kbd> : `[1;3B`
 -  <kbd>CTRL</kbd> + <kbd>F3</kbd> : `[1;5R`
 -  <kbd>CTRL</kbd> + <kbd>F4</kbd> : `[1;5S`
 -  <kbd>CTRL</kbd> + <kbd>SHIFT</kbd> + F3 : `[1;6R`
 -  <kbd>CTRL</kbd> + <kbd>SHIFT</kbd> + F4 : `[1;6S`
 -  <kbd>SHIFT</kbd> + <kbd>ALT</kbd> + <kbd>LEFT</kbd> : `[1;4D`
 -  <kbd>SHIFT</kbd> + <kbd>ALT</kbd> + <kbd>RIGHT</kbd> : `[1;4C`
 -  <kbd>SHIFT</kbd> + <kbd>ALT</kbd> + <kbd>UP</kbd> : `[1;4A`
 -  <kbd>SHIFT</kbd> + <kbd>ALT</kbd> + <kbd>DOWN</kbd> : `[1;4B`
 -  <kbd>CTRL</kbd> + <kbd>F5</kbd> : `[15;5~`
 -  <kbd>CTRL</kbd> + <kbd>SHIFT</kbd> + <kbd>F5</kbd> : `[15;6~`
 -  <kbd>ALT</kbd> + <kbd>F6</kbd> : `[17;3~`
 -  <kbd>CTRL</kbd> + <kbd>F6</kbd> : `[17;5~`
 -  <kbd>ALT</kbd> + <kbd>PPAGE</kbd> : `[5;3~`
 -  <kbd>ALT</kbd> + <kbd>NPAGE</kbd> : `[6;3~`
 -  <kbd>CTRL</kbd> + <kbd>F8</kbd> : `[19;5~`
 -  <kbd>ALT</kbd> + <kbd>SHIFT</kbd> + <kbd>F8</kbd> : `[19;4~`
 -  <kbd>CTRL</kbd> + <kbd>SHIFT</kbd> + <kbd>F8</kbd> : `[19;6~`
 -  <kbd>CTRL</kbd> + <kbd>F9</kbd> : `[20;5~`
 -  <kbd>ALT</kbd> + <kbd>F11</kbd> : `[23;3~`
 -  <kbd>CTRL</kbd> + <kbd>F11</kbd> : `[23;5~`
 -  <kbd>ALT</kbd> + <kbd>F12</kbd> : `[24;3~`
 -  <kbd>CTRL</kbd> + <kbd>F12</kbd> : `[24;5~`
 -  <kbd>ALT</kbd> + <kbd>INS</kbd>: `[2;3~`
 
 Possibly getting [this](http://stratus3d.com/blog/2015/02/28/sync-iterm2-profile-with-dotfiles-repository/) to work, needs testing.


## VIM Setup
My dotvim configuration can be cloned from github. The procedure is as follows:

```bash
$ rm -rf ~/.vim
$ git clone https://github.com/benjaminaltieri/dotvim ~/.vim
$ cd ~/.vim
$ ./setup.sh
```

## Python
Python is installed by homebrew (or by default macOS if you chose not to install it) but we need some other tools to make our python world a bit easier:

### Virtualenv and virtualenvwrapper
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

###Special packages
Some key packages with setup steps:

- awscli - I install and configure in a virtualenv.

```bash
$ mkvirtualenv aws_env
...
(aws_env) $ pip install --upgrade awscli
...
(aws_env) $ aws --version
aws-cli/1.14.14 Python/2.7.14 Darwin/17.3.0 botocore/1.8.18
(aws_env) $ aws configure
AWS Access Key ID [None]: ******
AWS Secret Access Key [None]: ******
Default region name [None]: us-west-2
Default output format [None]:
(aws_env) $ deactivate
$ echo 'all done!'
all done!
```

##Swift Specific Setup Steps

### Git Aliases
* `cob` - checkout new branch with the username/(input to cob command) format
* `pn` - push the current branch with the -u option to set up tracking (stands for 'push new')
* `au` - add previously tracked files to index (add -u)
* `bdel` - delete branch locally and remotely (as long as they share the same name)

### GDB Setup
You must codesign the binary following the [instructions](https://sourceware.org/gdb/wiki/BuildingOnDarwin).

Add this line: `echo "set startup-with-shell off" >> ~/.gdbinit`
