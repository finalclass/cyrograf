" Indentation for Cyrograf contracts: two spaces per brace level.
if exists('b:did_indent')
  finish
endif
let b:did_indent = 1

setlocal indentexpr=GetCyrografIndent()
setlocal indentkeys=0{,0},!^F,o,O
setlocal nosmartindent

let b:undo_indent = 'setlocal indentexpr< indentkeys< smartindent<'

function! s:Depth(lnum) abort
  let depth = 0
  let lnum = 1
  while lnum <= a:lnum
    let line = getline(lnum)
    let comment = stridx(line, '//')
    let code = comment >= 0 ? strpart(line, 0, comment) : line
    let depth += count(code, '{')
    let depth -= count(code, '}')
    if depth < 0
      let depth = 0
    endif
    let lnum += 1
  endwhile
  return depth
endfunction

function! GetCyrografIndent() abort
  let prev = prevnonblank(v:lnum - 1)
  if prev == 0
    return 0
  endif
  let depth = s:Depth(prev)
  if getline(v:lnum) =~# '^\s*}'
    let depth -= 1
  endif
  if depth < 0
    let depth = 0
  endif
  return depth * shiftwidth()
endfunction