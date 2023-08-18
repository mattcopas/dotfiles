#!/bin/bash
 
relative_directory=$(dirname "$0")
dotfiles_directory=$(realpath $relative_directory)
config_directory="$HOME/config/nvim"
mkdir -p $config_directory
echo "Creating symlink for $config_directory/init.vim to $dotfiles_directory/init.vim"
# ln -s <real_file> <link>
ln -s -f $dotfiles_directory/init.vim $config_directory/init.vim
