" Set the statusline of the current window {{{
function! compile#set_status(main, ...)
  let text = "Compilation: [" . a:main

  if exists("a:1")
    if exists("a:2")
      let text .= "%#" . a:2 . "#"
    endif

    let text .= a:1
  endif

  let text .= "%*]"
  let &l:statusline = text
endfunction
" }}}
" The timer for measuring the time taken by the script {{{
function! compile#timer(timer)
  let b:compile_time += 1
endfunction
" }}}
" Handler for output of the compilation {{{
function! compile#handler_output(job_id, data, event) dict
  let data = a:data[:-2]

  if len(data) == 0
    if strlen(a:data[0]) > 0
      let data = a:data[:-1]
    endif
  else
    call add(data, "")
  endif

  call appendbufline(self.buffer, "$", data)
endfunction
" }}}
" Handler for the exit event of the compilation {{{
function compile#handler_exit(job_id, data, event) dict
  call timer_stop(b:compile_timer)

  let msg = a:data == 0 ? "succeeded" : "failed"
  let msg = "Command " . msg . " with exit value " . a:data
  let msg .= " in " . b:compile_time . " second"

  if b:compile_time != 1
    let msg .= "s"
  endif

  call appendbufline(self.buffer, "$", msg)

  let exit_color = a:data == 0 ? "Good" : "Error"
  call compile#set_status("Exit ", a:data, "Compile" . exit_color)
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

  let b:compile_time = 0
  let b:compile_timer = timer_start(1000, function('compile#timer'), {'repeat': -1})

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
  syntax match compileError '\(warning\|error\|failed\):\?'
  syntax match compileError 'Segmentation fault'

  syntax match compileFile '^\f\+:'he=e-1
  syntax match compileFileNum '^\f\+:[0-9]\+'
  syntax match compileFileNum '^\f\+:[0-9]\+:[0-9]\+'

  syntax match Number '[0-9]'
  syntax match String "\('[^']*'\|\"[^\"]*\"\)"
  syntax match String "`\([^']*'\|[^\"]*\"\)"
  syntax match String "^\s*+\s*.*"

  syntax match compileCommand '\%1l`.*`$'hs=s+1,he=e-1
  syntax keyword compileGood succeeded
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
  call compile#set_status("Running")

  let b:compile_command = a:command

  call compile#add_highlights()
  call compile#add_mappings()
  call compile#execute()
endfunction
" }}}
" Interactive function for compilation {{{
function! compile#input()

  echohl compilePrompt
  let command = input("Compile: ", g:compile#previous_command)
  echohl Normal
  mode

  if empty(command)
    return
  endif

  let g:compile#previous_command = command
  let command = join(map(split(command, '\ze[<%#]'), 'expand(v:val)'), '')
  let command = substitute(command, "'", "'\"'\"'", "g")

  call compile#open(command)
endfunction
" }}}
