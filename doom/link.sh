#!/bin/bash
 
relative_directory=$(dirname "$0")
directory=$(realpath $relative_directory)
doom_dir=$(realpath ~/.doom.d)
emacs_dir=$(realpath ~/.emacs.d)
ispell_config_dir=$(realpath $emacs_dir/.local/etc/ispell)
echo "Creating symlinks from $doom_dir to $directory"
# ln -s <real_file> <link>
ln -s -f $directory/config.el $doom_dir/config.el
ln -s -f $directory/packages.el $doom_dir/packages.el
ln -s -f $directory/init.el $doom_dir/init.el

echo "Linking personal spelling file to emacs ispell config"
mkdir -p $ispell_config_dir
ln -s -f $directory/.pws $ispell_config_dir/.pws
