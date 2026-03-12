#!/usr/bin/env bash

relative_directory=$(dirname "$0")
dotfiles_directory=$(realpath $relative_directory)
config_directory="$HOME/.config/nvim"
echo "Creating symlink for $config_directory to $dotfiles_directory/nvim"
# ln -s <real_file> <link>
ln -s -f $dotfiles_directory/nvim-kickstart $config_directory
