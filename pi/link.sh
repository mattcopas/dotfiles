#!/usr/bin/env bash
 
relative_directory=$(dirname "$0")
dotfiles_directory=$(realpath $relative_directory)
agent_directory="${dotfiles_directory}/agent"
pi_directory=$HOME/.pi
pi_agent_directory="${pi_directory}/agent"

ln -s -f "${agent_directory}/AGENTS.md" "$pi_agent_directory/AGENTS.md"
ln -s -f "${agent_directory}/models.json" "$pi_agent_directory/models.json"
ln -s -f "${agent_directory}/settings.json" "$pi_agent_directory/settings.json"
