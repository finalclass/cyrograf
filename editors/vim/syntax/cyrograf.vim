" Syntax highlighting for Cyrograf contracts.
if exists('b:current_syntax')
  finish
endif

syntax match cyrografDeclarationStruct "\<\(struct\|variant\)\>\ze\s\+[A-Z][A-Za-z0-9_]*"
syntax match cyrografDeclarationRpc "\<rpc\>\ze\s\+[a-z][A-Za-z0-9_]*" nextgroup=cyrografMethod skipwhite

syntax keyword cyrografPrimitive String Int Float Bool Void Date Record List

syntax match cyrografType "\<[A-Z][A-Za-z0-9_]*\>"

syntax match cyrografField "^\s*\zs[a-z][A-Za-z0-9_]*\ze\s*[?]*\s*:"
syntax match cyrografMethod "[a-z][A-Za-z0-9_]*" contained

syntax match cyrografOperator "->"
syntax match cyrografPunctuation "[{}\[\]():?;.,<>]"

syntax region cyrografComment start="//" end="$"

highlight def link cyrografDeclarationStruct Keyword
highlight def link cyrografDeclarationRpc Keyword
highlight def link cyrografPrimitive Type
highlight def link cyrografType Type
highlight def link cyrografField Identifier
highlight def link cyrografMethod Function
highlight def link cyrografOperator Operator
highlight def link cyrografPunctuation Delimiter
highlight def link cyrografComment Comment

let b:current_syntax = 'cyrograf'