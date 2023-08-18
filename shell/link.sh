dotfiles_directory=$HOME/git/dotfiles
shell_directory=$dotfiles_directory/shell
rc_file="$HOME/.zshrc"

echo "Sourcing dotfiles from $shell_directory to $rc_file"
# Is there a better way to do this? zshrc tends to get modified across envs (usually for path stuff)
# Perhaps zshrc should reference a path dotfile or something (if it exists)

source_dotfile () {
  local file=$1
  local line_to_append="source $shell_directory/$file"
  if [ $(grep -c "$line_to_append" "$rc_file") -gt 0 ] 
  then
    echo "Line '$line_to_append' already eists in $rc_file"
  else
    echo "Adding $file to $rc_file"
    echo "$line_to_append" >> $rc_file
  fi
}

source_dotfile alias
source_dotfile functions
source_dotfile env
