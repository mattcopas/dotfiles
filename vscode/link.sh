#!/usr/bin/env bash
relative_script_directory="$(dirname "$0")"
absolute_script_directory="$(realpath $relative_script_directory)"

unameOS="$(uname -s)"
case "$unameOS" in 
  Darwin*) os=Mac;;
  Linux*) os=Linux;;
  *)
    echo "Unknown uname operating system: $unameOS"
    exit 1
    ;;

esac

case "$os" in
  Mac*) vscode_user_directory="$HOME/Library/Application Support/Code/User";;
  Linux*) vscode_user_directory="$HOME/.config/Code - OSS/User";;
esac

function link_file() {
  local file_name="$1"
  echo "Linking vscode $file_name for operating system $os"
  ln -sf "$absolute_script_directory/$file_name" "$vscode_user_directory/$file_name"
}

# Builds and installs the orgflow extension. Only runs with --extension, because it needs npm
function install_orgflow() {
  echo "Building and installing orgflow"
  (
    cd "$absolute_script_directory/orgflow" &&
      npm ci &&
      npm run package &&
      code --install-extension "orgflow-$(node -p "require('./package.json').version").vsix" --force
  )
}

link_file keybindings.json
link_file settings.json

if [[ "${1:-}" == "--extension" ]]; then
  install_orgflow
fi
