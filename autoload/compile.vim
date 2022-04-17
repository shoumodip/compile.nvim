" Set the statusline of the current window
function! compile#set_status(text, ...)
    let text = "Compilation: "

    if exists("a:1")
        let text .= "%#" . a:1 . "#"
    endif

    let text .= a:text . "%*"
    let &l:statusline = text
endfunction

" Handler for the compilation
function! compile#handler(job_id, data, event) dict
    if a:event == 'exit'
        let msg = "Command "
        if a:data == 0
            let msg .= "finished"
        else
            let msg .= "exited abnormally with exit code " . a:data
        endif

        call setbufvar(self.buffer, "&modifiable", 1)
        call appendbufline(self.buffer, "$", add(self.output, msg))
        call setbufvar(self.buffer, "&modifiable", 0)

        let exit_color = a:data == 0 ? "Good" : "Bad"
        call compile#set_status("exit " . a:data, "Compile" . exit_color)
    else
        let self.output[-1] .= a:data[0]
        call extend(self.output, a:data[1:])
        let str = self.output[:-2]
        let self.output = [self.output[-1]]

        call setbufvar(self.buffer, "&modifiable", 1)
        call appendbufline(self.buffer, '$', l:str)
        call setbufvar(self.buffer, "&modifiable", 0)
    end
endfunction

" The callbacks for the job control
let g:compile#callbacks = {
            \ 'on_stdout': function('compile#handler'),
            \ 'on_stderr': function('compile#handler'),
            \ 'on_exit': function('compile#handler')
            \ }

" Execute the compilation command
function! compile#execute()
    if g:compile#auto_save
        silent! wa
    endif

    call setbufvar(bufnr(), "&modifiable", 1)
    silent! normal! gg"_dG
    call setbufline(bufnr(), 1, ["Executing `" . b:compile_command . "`", ""])
    call setbufvar(bufnr(), "&modifiable", 0)

    let b:compile_start = reltime()
    let b:compile_job = jobstart(['sh', '-c', b:compile_command],
                \ extend({'buffer': bufnr(), 'output': ['']}, g:compile#callbacks))
endfunction

" Edit the compilation command
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

" Open the file under the cursor, works like gF
function! compile#open_file()
    let line = getline(".")[col(".") - 1:]

    if strlen(matchstr(line, '^\f\+:\s*\d\+')) == 0
        normal! j
        return
    endif

    let compiler_buffer = bufnr()

    silent! normal! gF

    if winnr("$") > 1
        let cursor_position = getpos(".")
        let cursor_position[2] = 0

        let file_buffer = bufnr()

        call win_gotoid(win_getid(winnr("#")))
        execute "buffer " . file_buffer

        call win_gotoid(win_getid(winnr("#")))
        execute "buffer " . compiler_buffer

        " Check if the column is also provided
        let col = 1
        if match(line, '^\f\+:\s*\d\+:\d\+') != -1
            let col = split(line, ":")[2]
        endif

        normal! zz

        call win_gotoid(win_getid(winnr("#")))
        call setpos(".", cursor_position)

        if col > 1
            execute "normal! " . (col - 1) . "l"
        endif
    endif
endfunction

function! compile#jump(rev)
    call win_gotoid(bufwinid("*compilation*"))
    call search('\f\+:\s*[0-9]\+\(:[0-9]\+\)\?', a:rev ? 'wb' : 'w')
    call compile#open_file()
endfunction

function! compile#restart()
    let id = bufwinid("*compilation*")
    if id == -1
        if buflisted("*compilation*")
            execute g:compile#open_command . " *compilation*"
            call compile#execute()
        else
            call compile#start()
        endif
    else
        call win_gotoid(id)
        call compile#execute()
    endif
endfunction

" Add the highlights
function! compile#add_highlights()
    syntax match compileLabel '^\f\+:'he=e-1
    syntax match compileFile '\f\+:\s*\d\+\(:\d\+\)\?'

    syntax match String "\('[^']*'\|\"[^\"]*\"\)"
    syntax match String "`\([^']*'\|[^\"]*\"\)"
    syntax match DiffAdded "^\s*+\s*.*"
    syntax match Number "exit code \d\+$"hs=s+10

    syntax match compileCommand '\%1l`.*`$'hs=s+1,he=e-1
    syntax match compileGood "\<finished\>"
    syntax match compileBad "\<exited abnormally\>"

    syntax keyword compileBad error
    syntax keyword compileLint note warning
endfunction

" Add the mappings
function! compile#add_mappings()
    nnoremap <buffer> <silent> r    :call compile#execute()<cr>
    nnoremap <buffer> <silent> q    :call compile#close()<cr>
    nnoremap <buffer> <silent> <cr> :call compile#open_file()<cr>
    nnoremap <buffer> <silent> e    :call compile#edit_command()<cr>
    nnoremap <buffer> <silent> n    :call compile#jump(0)<cr>
    nnoremap <buffer> <silent> p    :call compile#jump(1)<cr>
endfunction

" Close the compilation window
function! compile#close()
    call jobstop(b:compile_job)

    try
        close
    catch /.*/
        bn
    endtry
endfunction

" Open the compilation window
function! compile#open(command)
    if bufwinid("*compilation*") == -1
        execute g:compile#open_command . " *compilation*"
        setlocal buftype=nofile
    endif

    call compile#set_status("running", "compileLabel")

    let b:compile_command = a:command

    call compile#add_highlights()
    call compile#add_mappings()
    call compile#execute()
endfunction

" The main compilation function
function! compile#main(command)
    let g:compile#previous_command = a:command
    call compile#open(join(map(split(a:command, '\ze[<%#]'), 'expand(v:val)'), ''))
endfunction

" Interactive function for compilation
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
