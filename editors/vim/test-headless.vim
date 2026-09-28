" Batch checks for the Cyrograf Vim integration.
"
" Run with:
"   vim -N -u NONE -i NONE -es \
"     --cmd 'let g:editors = "/path/to/editors"' -S test-headless.vim
"
" Results are appended to $CYROGRAF_VIM_OUT as PASS:/FAIL: lines.

let s:out = $CYROGRAF_VIM_OUT
let s:fixture = $CYROGRAF_VIM_FIXTURE
let s:failures = 0

call writefile([], s:out)

function! CyrografCheck(label, condition) abort
  call writefile([(a:condition ? 'PASS: ' : 'FAIL: ') . a:label], s:out, 'a')
  if !a:condition
    let s:failures += 1
  endif
endfunction

function! CyrografSyn(pattern) abort
  for lnum in range(1, line('$'))
    let col = match(getline(lnum), a:pattern)
    if col >= 0
      return synIDattr(synID(lnum, col + 1, 1), 'name')
    endif
  endfor
  return ''
endfunction

function! CyrografFindLine(pattern) abort
  for lnum in range(1, line('$'))
    if match(getline(lnum), a:pattern) >= 0
      return lnum
    endif
  endfor
  return 0
endfunction

function! CyrografGroupAt(lnum, pattern) abort
  if a:lnum == 0
    return ''
  endif
  let col = match(getline(a:lnum), a:pattern)
  return col >= 0 ? synIDattr(synID(a:lnum, col + 1, 1), 'name') : ''
endfunction

execute 'set runtimepath^=' . g:editors . '/vim'
filetype plugin indent on
syntax enable

execute 'edit ' . fnameescape(s:fixture)
call CyrografCheck('filetype detected as cyrograf', &filetype ==# 'cyrograf')
call CyrografCheck('line comment recognized', &commentstring ==# '// %s')
call CyrografCheck('ftplugin loaded', exists('b:did_ftplugin'))
call CyrografCheck('indent script loaded', exists('b:did_indent'))
call CyrografCheck('struct highlighted as declaration',
      \ CyrografSyn('struct') ==# 'cyrografDeclarationStruct')
call CyrografCheck('variant highlighted as declaration',
      \ CyrografSyn('variant') ==# 'cyrografDeclarationStruct')
call CyrografCheck('rpc highlighted as declaration',
      \ CyrografSyn('rpc') ==# 'cyrografDeclarationRpc')
call CyrografCheck('primitive highlighted',
      \ CyrografSyn('String') ==# 'cyrografPrimitive')
call CyrografCheck('message name highlighted as type',
      \ CyrografSyn('Reservation') ==# 'cyrografType')
call CyrografCheck('field highlighted',
      \ CyrografSyn('owner_id') ==# 'cyrografField')
call CyrografCheck('method highlighted',
      \ CyrografSyn('reserve') ==# 'cyrografMethod')
call CyrografCheck('comment highlighted',
      \ CyrografSyn('//') ==# 'cyrografComment')

enew
setlocal filetype=cyrograf
call setline(1, ['struct A {', 'field: String', '}'])
normal! gg=G
call CyrografCheck('brace indentation uses two spaces',
      \ getline(2) ==# '  field: String')
call CyrografCheck('closing brace returns to column zero',
      \ getline(3) ==# '}')

" Markdown fenced `cyrograf' blocks through the classic syntax mechanism.
let g:markdown_fenced_languages = ['cyrograf']
let s:markdown = tempname() . '.md'
call writefile([
      \ '# Example',
      \ '',
      \ '```cyrograf',
      \ '// <b>&</b> comment',
      \ 'struct Marked {',
      \ '  item: String',
      \ '}',
      \ '```',
      \ '',
      \ 'prose stays prose',
      \ '',
      \ '````cyrograf',
      \ '```',
      \ 'struct Longer {',
      \ '}',
      \ '````',
      \ '',
      \ '```json',
      \ 'struct NotCyrograf {}',
      \ '```',
      \ ], s:markdown)
execute 'edit! ' . fnameescape(s:markdown)
setlocal filetype=markdown
call CyrografCheck('markdown filetype selected', &filetype ==# 'markdown')
let s:decl = CyrografFindLine('struct Marked')
call CyrografCheck('markdown block declaration highlighted',
      \ CyrografGroupAt(s:decl, 'struct') ==# 'cyrografDeclarationStruct')
call CyrografCheck('markdown block primitive highlighted',
      \ CyrografGroupAt(CyrografFindLine('item: String'), 'String') ==# 'cyrografPrimitive')
call CyrografCheck('markdown block comment highlighted',
      \ CyrografGroupAt(CyrografFindLine('// <b>'), '//') ==# 'cyrografComment')
call CyrografCheck('shorter backtick run inside a longer fence does not close it',
      \ CyrografGroupAt(CyrografFindLine('struct Longer'), 'struct') ==# 'cyrografDeclarationStruct')
call CyrografCheck('prose after the fence is not cyrograf',
      \ CyrografGroupAt(CyrografFindLine('prose stays prose'), 'prose') !=# 'cyrografDeclarationStruct')
call CyrografCheck('other language block is not cyrograf',
      \ CyrografGroupAt(CyrografFindLine('struct NotCyrograf'), 'struct') !=# 'cyrografDeclarationStruct')
call delete(s:markdown)

if s:failures > 0
  cquit
endif
qall!