let s:compile_buffer_name = "*compilation*"

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

    let buffer = bufnr()
    call sign_unplace('*', {'buffer': buffer})

    call setbufvar(buffer, "&modifiable", 1)
    silent! normal! gg"_dG
    call setbufline(buffer, 1, ["Executing `" . b:compile_command . "`", ""])
    call setbufvar(buffer, "&modifiable", 0)

    let b:compile_start = reltime()
    let b:compile_job = jobstart(['sh', '-c', b:compile_command],
                \ extend({'buffer': buffer, 'output': ['']}, g:compile#callbacks))
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

    let line = split(line, ":")

    let buffer = bufnr()
    call sign_unplace('*', {'buffer': buffer})
    call sign_place(69, '', 'CompilationCurrent', buffer, {'lnum': line(".")})

    normal! zz
    wincmd p

    try
        execute "buffer " . line[0]
    catch /.*/
        execute "edit " . line[0]
    endtry

    let position = [buffer, str2nr(line[1]), 0, 0]

    if len(line) > 2
        let position[2] = str2nr(line[2])
    endif

    call setpos(".", position)
endfunction

" Jump to the next or previous location in the compilation output
function! compile#jump(rev)
    if !buflisted(s:compile_buffer_name)
        call compile#start()
        return
    endif

    let window = bufwinid(s:compile_buffer_name)

    if window == -1
        execute g:compile#open_command . " " . s:compile_buffer_name
    else
        call win_gotoid(window)
    endif

    call search('\f\+:\s*[0-9]\+\(:[0-9]\+\)\?', a:rev ? 'wb' : 'w')
    call compile#open_file()
endfunction

function! compile#restart()
    let id = bufwinid(s:compile_buffer_name)
    if id == -1
        if buflisted(s:compile_buffer_name)
            execute g:compile#open_command . " " . s:compile_buffer_name
            call jobstop(b:compile_job)
            call compile#execute()
        else
            call compile#start()
        endif
    else
        call win_gotoid(id)
        call jobstop(b:compile_job)
        call compile#execute()
    endif
endfunction

" Add the highlights
function! compile#add_highlights()
    syntax match Number "exit code \d\+$"hs=s+10
    syntax match compileLabel '^\f\+:'he=e-1
    syntax match compileFile '\f\+:\s*\d\+\(:\d\+\)\?'
    syntax match compileCommand '\%1l`.*`$'hs=s+1,he=e-1
    syntax match compileGood "\<finished\>"
    syntax match compileBad "\<exited abnormally\>"

    syntax keyword compileBad error
    syntax keyword compileLint note hint warning
endfunction

" Add the mappings
function! compile#add_mappings()
    nnoremap <buffer> <silent> r     :call compile#execute()<cr>
    nnoremap <buffer> <silent> q     :call compile#close()<cr>
    nnoremap <buffer> <silent> <cr>  :call compile#open_file()<cr>
    nnoremap <buffer> <silent> e     :call compile#edit_command()<cr>
    nnoremap <buffer> <silent> n     :call compile#jump(0)<cr>
    nnoremap <buffer> <silent> p     :call compile#jump(1)<cr>
    nnoremap <buffer> <silent> <c-c> :call jobstop(b:compile_job)<cr>
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
    if bufwinid(s:compile_buffer_name) == -1
        execute g:compile#open_command . " " . s:compile_buffer_name
        setlocal buftype=nofile
        setlocal nocursorline nocursorcolumn
    endif

    let b:compile_command = a:command

    call compile#add_highlights()
    call compile#add_mappings()
    call compile#execute()
endfunction

" The main compilation function
function! compile#main(command)
    let g:compile#previous_command = a:command
    call compile#open(a:command)
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
