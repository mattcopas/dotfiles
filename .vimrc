" Uncommant to install plugins
" source .vimrc-load-plugins

" Change <leader> to Spacebar
map <Space> <leader>

set number
set relativenumber
syntax on

set hlsearch " use :nohl to remove highlighting after search
set incsearch

set scrolloff=8 " start scrolling when cursor is 8 lines from the bottom


set ignorecase smartcase " Ignore case in searches unless a capital is present

set path+=**
set wildmenu " Display matching files on tab completion
set wildignore=.swp

set noswapfile

set noerrorbells

" Set tab to 2 spaces
set tabstop=2 softtabstop=0 expandtab shiftwidth=2 smarttab
set smartindent

if $TERM == 'screen'
  " Workaround to get colors to work in tmux
  set t_Co=256
endif
set background=dark
" Current line highlighting
" set cursorline 
" Highlight current line
" highlight CursorLine guifg=white guibg=darkblue ctermfg=white ctermbg=darkblue
" Change colour of highlight when entering/leaving insert mode
" autocmd InsertEnter * highlight CursorLine guifg=white guibg=darkblue ctermfg=white ctermbg=darkgreen
" autocmd InsertLeave * highlight CursorLine guifg=white guibg=darkblue ctermfg=white ctermbg=darkblue

"Display error when using arrow keys in normal mode
noremap <up>    :echom 'USE K TO GO UP'<CR>
noremap <down>  :echom 'USE J TO GO DOWN'<CR>
noremap <left>  :echom 'USE H TO GO LEFT'<CR>
noremap <right> :echom 'USE L TO GO RIGHT'<CR>
inoremap <up>    <ESC>:echom 'USE K TO GO UP'<CR>
inoremap <down>  <ESC>:echom 'USE J TO GO DOWN'<CR>
inoremap <right> <ESC>:echom 'USE L TO GO RIGHT'<CR>
inoremap <left>  <ESC>:echom 'USE H TO GO LEFT'<CR>  
