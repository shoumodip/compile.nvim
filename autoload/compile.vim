" Set the statusline of the current window {{{
function! compile#set_status(text, ...)
  let text = "Compilation: "

  if exists("a:1")
    let text .= "%#" . a:1 . "#"
  endif

  let text .= a:text . "%*"
  let &l:statusline = text
endfunction
" }}}
" Handler for output of the compilation {{{
function! compile#handler_output(job_id, data, event) dict

  let data = join(a:data, "\n")
  let data_list = split(data, "\n")

  if strlen(data) == 0
    return
  endif

  if count(data, "\n") == len(data_list)
    call appendbufline(self.buffer, "$", data_list[:-1])
    let b:compile_buffered = 0
  else
    let lines = getbufline(self.buffer, 1, "$")
    let len = len(lines)

    if len < 3
      call appendbufline(self.buffer, "$", repeat([""], 3 - len))
    endif

    call setbufline(self.buffer, "$", split(lines[-1] . data, "\n"))

    let b:compile_buffered = 1
  endif

endfunction
" }}}
" Handler for the exit event of the compilation {{{
function compile#handler_exit(job_id, data, event) dict
  if !exists("b:compile_command")
    return
  endif

  let msg = a:data == 0 ? "finished" : "failed"
  let msg = "Command " . msg . " with exit value " . a:data
  let msg .= " at " . strftime("%H:%M:%S %a %d %b %Y")

  if !b:compile_buffered
    let msg = ["", msg]
  endif

  call appendbufline(self.buffer, "$", msg)

  let exit_color = a:data == 0 ? "Good" : "Bad"
  call compile#set_status("exit " . a:data, "Compile" . exit_color)
endfunction
" }}}
" The callbacks for the job control {{{
let g:compile#callbacks = {
      \ 'on_stdout': function('compile#handler_output'),
      \ 'on_stderr': function('compile#handler_output'),
      \ 'on_exit': function('compile#handler_exit')
      \ }
" }}}
" Execute the compilation command {{{
function! compile#execute()
  silent! normal! gg"_dG
  call setbufline(bufnr(), 1, ["Executing `" . b:compile_command . "`", ""])

  let b:compile_job = jobstart(['sh', '-c', b:compile_command], extend({'buffer': bufnr()}, g:compile#callbacks))
endfunction
" }}}
" Edit the compilation command {{{
function! compile#edit_command()
  echohl compilePrompt
  let command = input("Compile: ", b:compile_command)
  echohl Normal
  mode

  if strlen(command) > 0
    let b:compile_command = command
    call compile#execute()
  endif
endfunction
" }}}
" Open the file under the cursor, works like gF {{{
function! compile#open_file()
  if strlen(matchstr(getline("."), '^\f\+:')) == 0
    normal! j
    return
  endif

  let compiler_buffer = bufnr()

  silent! normal! gF

  if winnr("$") > 1
    let cursor_position = getpos(".")
    let file_buffer = bufnr()

    silent! call win_gotoid(win_getid(winnr("#")))
    execute "buffer " . file_buffer

    silent! call win_gotoid(win_getid(winnr("#")))
    execute "buffer " . compiler_buffer

    silent! call win_gotoid(win_getid(winnr("#")))
    call setpos(".", cursor_position)
  endif
endfunction
" }}}
" Add the highlights {{{
function! compile#add_highlights()
  syntax match compileLabel '^\f\+:'he=e-1
  syntax match compileFile '\f\+:\s*[0-9]\+'
  syntax match compileFile '\f\+:\s*[0-9]\+:[0-9]\+'

  syntax match Number 'exit value [0-9]\+ at ..:..:..'hs=s+11,he=e-12

  syntax match String "\('[^']*'\|\"[^\"]*\"\)"
  syntax match String "`\([^']*'\|[^\"]*\"\)"
  syntax match DiffAdded "^\s*+\s*.*"

  syntax match compileCommand '\%1l`.*`$'hs=s+1,he=e-1

  syntax keyword compileGood finished succeeded
  syntax keyword compileBad warning error failed
endfunction
" }}}
" Add the mappings {{{
function! compile#add_mappings()
  nnoremap <buffer> <silent> r    :call compile#execute()<cr>
  nnoremap <buffer> <silent> q    :call compile#close()<cr>
  nnoremap <buffer> <silent> <cr> :call compile#open_file()<cr>
  nnoremap <buffer> <silent> e    :call compile#edit_command()<cr>
endfunction
" }}}
" Delete the compilation buffer {{{
function! compile#close()
  silent! call jobstop(b:compile_job)
  bdelete!
endfunction
" }}}
" Open the compilation window {{{
function! compile#open(command)
  execute g:compile#open_command . " *compilation*"

  setlocal buftype=nofile
  call compile#set_status("running", "compileLabel")

  let b:compile_command = a:command
  let b:compile_buffered = 1

  call compile#add_highlights()
  call compile#add_mappings()
  call compile#execute()
endfunction
" }}}
" The main compilation function {{{
function! compile#main(command)
  let g:compile#previous_command = a:command

  let command = join(map(split(a:command, '\ze[<%#]'), 'expand(v:val)'), '')
  let command = substitute(command, "'", "'\"'\"'", "g")

  call compile#open(command)
endfunction
" }}}
" Interactive function for compilation {{{
function! compile#start(...)

  if exists("a:1")
    call compile#main(a:1)
    return
  endif

  echohl compilePrompt
  let command = input("Compile: ", g:compile#previous_command)
  echohl Normal
  mode

  if empty(command)
    return
  endif

  call compile#main(command)
endfunction
" }}}
