""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Plugins from Vim Plug Package Manger - https://github.com/junegunn/vim-plug
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Run :PlugInstall to install any listed plugins here
" Run :PlugClean to remove any unused plugins that were previously installed

" Specify a directory for plugins
" - For Neovim: ~/.local/share/nvim/plugged
" - Avoid using standard Vim directory names like 'plugin'
call plug#begin('~/.vim/plugged')

" Shorthand notation fetches from GitHub
Plug 'rafi/awesome-vim-colorschemes'

" Initialize plugin system
call plug#end()
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Keep visual mode enabled after indent
:vnoremap < <gv
:vnoremap > >gv

" Turn on syntax highlighting
syntax on
colorscheme dracula

" Set line numbers on 
set number

" Set highlight search on 
set hlsearch

" Set tab to 2 spaces
set tabstop=2 softtabstop=0 expandtab shiftwidth=2 smarttab

" Auto close stuff

inoremap " ""<left>
inoremap ' ''<left>
inoremap ( ()<left>
inoremap [ []<left>
inoremap { {}<left>
inoremap < <><left>
" Auto close and indent after pressing enter
inoremap {<CR> {<CR>}<ESC>O<TAB>
inoremap [<CR> [<CR>]<ESC>O<TAB>
inoremap (<CR> (<CR>)<ESC>O<TAB>
