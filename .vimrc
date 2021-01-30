try
  " Plugins will be downloaded under the specified directory.
  call plug#begin('~/.vim/plugged')
  Plug 'tpope/vim-fugitive'
  Plug 'morhetz/gruvbox'
  " List ends here. Plugins become visible to Vim after this call.
  call plug#end()
catch
  echo "vim-plug error - not installed?"
endtry

" use grivbox color scheme
colorscheme gruvbox

" Change <leader> to Spacebar
let mapleader = " " 
set number
set relativenumber
syntax on

set hlsearch
set incsearch


set ignorecase smartcase " Ignore case in searches unless a capital is present

set path+=**
set wildmenu " Display matching files on tab completion
set wildignore=.swp
nnoremap <leader>f :find *

set noerrorbells

" Set tab to 2 spaces
set tabstop=2 softtabstop=0 expandtab shiftwidth=2 smarttab
set smartindent

set background=dark
" Current line highlighting
" set cursorline 
" Highlight current line
" highlight CursorLine guifg=white guibg=darkblue ctermfg=white ctermbg=darkblue
" Change colour of highlight when entering/leaving insert mode
" autocmd InsertEnter * highlight CursorLine guifg=white guibg=darkblue ctermfg=white ctermbg=darkgreen
" autocmd InsertLeave * highlight CursorLine guifg=white guibg=darkblue ctermfg=white ctermbg=darkblue
