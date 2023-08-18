#!/bin/bash
 
relative_directory=$(dirname "$0")
directory=$(realpath $relative_directory)
doom_dir=$(realpath ~/.doom.d)
echo "Creating symlinks from $doom_dir to $directory"
# ln -s <real_file> <link>
ln -s -f $directory/config.el $doom_dir/config.el
ln -s -f $directory/packages.el $doom_dir/packages.el
ln -s -f $directory/init.el $doom_dir/init.el
