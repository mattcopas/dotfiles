#!/bin/bash
 
relative_directory=$(dirname "$0")
dotfiles_directory=$(realpath $relative_directory)
ln -s -f $dotfiles_directory/.zshrc $HOME/.zshrc
