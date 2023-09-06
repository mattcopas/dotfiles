relative_script_directory="$(dirname "$0")"
absolute_script_directory="$(realpath $relative_script_directory)"

unameOS="$(uname -s)"
case "$unameOS" in 
  Darwin*) os=Mac;;
  *)
    echo "Unknown uname operating system: $unameOS"
    exit 1
    ;;

esac

function link_keybindings() {
  echo "Linking vscode keybindings for operating system $os"
  case "$os" in
    Mac*) vscode_keybindings_path="$HOME/Library/Application Support/Code/User/keybindings.json";;
    *)
      echo "Unknown operating system $os"
      exit 1
      ;;
  esac


  dotfile_keybindings_path="$absolute_script_directory/keybindings.json"
  echo "Linking dotfile keybindings $dotfile_keybindings_path to vscode path $vscode_keybindings_path"

  ln -sf "$dotfile_keybindings_path" "$vscode_keybindings_path"
}

link_keybindings
