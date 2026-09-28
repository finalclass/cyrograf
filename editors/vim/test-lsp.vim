" Batch checks for the Cyrograf Vim integration with yegappan/lsp.
"
" Run with:
"   vim -N -u NONE -i NONE -es \
"     --cmd 'let g:editors = "/path/to/editors"' -S test-lsp.vim
"
" Environment:
"   CYROGRAF_VIM_LSP_PLUGIN   yegappan/lsp checkout
"   CYROGRAF_VIM_LSP_BIN      cyrograf program path (may contain spaces)
"   CYROGRAF_VIM_LSP_CLI_BIN  cyrograf program for the CLI comparison
"   CYROGRAF_VIM_LSP_PROJECT  temporary project directory
"   CYROGRAF_VIM_LSP_OUT      report file

let s:out = $CYROGRAF_VIM_LSP_OUT
let s:failures = 0

call writefile([], s:out)

function! CyrografLspCheck(label, condition) abort
  call writefile([(a:condition ? 'PASS: ' : 'FAIL: ') . a:label], s:out, 'a')
  if !a:condition
    let s:failures += 1
  endif
endfunction

function! CyrografLspWait(predicate, timeout_ms) abort
  let l:start = reltime()
  while reltimefloat(reltime(l:start)) * 1000 < a:timeout_ms
    if a:predicate()
      return 1
    endif
    sleep 100m
  endwhile
  return a:predicate()
endfunction

function! CyrografLspWaitFalse(predicate, timeout_ms) abort
  return !CyrografLspWait(a:predicate, a:timeout_ms)
endfunction

function! CyrografLspErrors() abort
  return lsp#lsp#ErrorCount().Error
endfunction

execute 'set runtimepath^=' . g:editors . '/vim'
execute 'set runtimepath^=' . fnameescape($CYROGRAF_VIM_LSP_PLUGIN)
let g:LSPTest = v:true
set nocompatible
syntax enable
filetype plugin indent on
source $CYROGRAF_VIM_LSP_PLUGIN/plugin/lsp.vim
call g:LspEnable()

call g:LspAddServer([{
      \ 'name': 'cyrograf',
      \ 'filetype': ['cyrograf'],
      \ 'path': $CYROGRAF_VIM_LSP_BIN,
      \ 'args': ['lsp', '--stdio'],
      \ 'syncInit': v:true,
      \ }])

execute 'edit ' . fnameescape($CYROGRAF_VIM_LSP_PROJECT . '/Orders.cyrograf')

call CyrografLspCheck('server ready',
      \ CyrografLspWait({-> g:LspServerReady()}, 30000))
call CyrografLspCheck('buffer listener attached',
      \ CyrografLspWait({-> len(getbufvar(bufnr(), 'LspListenerIds', [])) > 0}, 30000))
call CyrografLspCheck('clean document has no diagnostics',
      \ CyrografLspWait({-> CyrografLspErrors() == 0}, 30000))

function! CyrografLspReferenceLine() abort
  for l:lnum in range(1, line('$'))
    if getline(l:lnum) =~# 'Common\.Thing'
      return l:lnum
    endif
  endfor
  return 0
endfunction

let s:line = CyrografLspReferenceLine()
call CyrografLspCheck('example carries the cross-module reference', s:line > 0)
execute 'silent! %s/Common\.Thing/Common.Missing/'
doautocmd BufWinEnter
redraw!
call CyrografLspCheck('edit applied to the buffer', getline(s:line) =~# 'Common\.Missing')
call CyrografLspCheck('unsaved error diagnosed',
      \ CyrografLspWait({-> CyrografLspErrors() > 0}, 30000))

execute 'silent! %s/Common\.Missing/Common.Thing/'
doautocmd BufWinEnter
redraw!
call CyrografLspCheck('diagnostics cleared after repair',
      \ CyrografLspWait({-> CyrografLspErrors() == 0}, 30000))

call cursor(s:line, match(getline(s:line), 'Common\.Thing') + 1)
execute 'LspGotoDefinition'
call CyrografLspCheck('definition opens the other module',
      \ CyrografLspWait({-> expand('%:t') ==# 'Common.cyrograf'}, 30000))

" Formatting through the client must equal the CLI formatter.
let s:messy = "struct   A{x:String;y?:Int}\n"
let s:file = $CYROGRAF_VIM_LSP_PROJECT . '/A.cyrograf'
call writefile(['struct   A{x:String;y?:Int}'], s:file)
execute 'edit ' . fnameescape(s:file)
call CyrografLspCheck('format project server ready',
      \ CyrografLspWait({-> g:LspServerReady()}, 30000))
call CyrografLspWait({-> CyrografLspErrors() == 0}, 30000)
execute 'LspFormat'
let s:expected = system($CYROGRAF_VIM_LSP_CLI_BIN . ' format --stdin --filename A.cyrograf',
      \ s:messy)
let s:expected = substitute(s:expected, '\n$', '', '')
call CyrografLspCheck('LSP formatting matches the CLI',
      \ CyrografLspWait({-> join(getline(1, '$'), "\n") ==# s:expected}, 30000))

if s:failures > 0
  cquit
endif
qall!