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


###VIM Setup
My dotvim configuration can be cloned from github. The procedure is as follows:

```bash
$ rm -rf ~/.vim
$ git clone https://github.com/benjaminaltieri/dotvim ~/.vim
$ cd ~/.vim
$ ./setup.sh
```
