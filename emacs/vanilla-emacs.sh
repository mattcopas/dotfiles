#! /usr/bin/env bash

relative_directory=$(dirname "$0")
script_directory=$(realpath $relative_directory)

#
# For older versions of emacs
# emacs -nw -q --load $script_directory/init.el

# Requires emacs 29+
emacs --init-directory $script_directory
