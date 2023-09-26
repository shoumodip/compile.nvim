local compile = {}

function compile.stop()
  if compile.stdout then
    compile.stdout:read_stop()
    compile.stdout:close()
    compile.stdout = nil
  end

  if compile.stderr then
    compile.stderr:read_stop()
    compile.stderr:close()
    compile.stderr = nil
  end

  if compile.handle then
    compile.handle:close()
    compile.handle = nil
  end
end

function compile.line(start, stop, data)
  vim.api.nvim_buf_set_option(compile.buffer, "modifiable", true)
  vim.api.nvim_buf_set_lines(compile.buffer, start, stop, false, data)
  vim.api.nvim_buf_set_option(compile.buffer, "modifiable", false)
end

function compile.read(_, data)
  if data then
    vim.schedule(function ()
      data = vim.split(compile.last..data, "\n")
      compile.last = data[#data]
      compile.line(-2, -1, data)
    end)
  end
end

function compile.run()
  vim.cmd("wall")

  if compile.handle then
    compile.stop()
  end

  vim.api.nvim_win_set_cursor(0, {1, 0})
  compile.line(0, -1, {"Executing `"..compile.command.."`", "", ""})

  compile.stdout = vim.loop.new_pipe()
  compile.stderr = vim.loop.new_pipe()

  local options = {
    args = {"-c", compile.command},
    stdio = {nil, compile.stdout, compile.stderr}
  }

  compile.handle = vim.loop.spawn("sh", options, vim.schedule_wrap(function (code)
    compile.stop()
    if code == 0 then
      compile.line(-1, -1, {"Compilation succeeded"})
    else
      compile.line(-1, -1, {"Compilation failed with exit code "..code})
    end
  end))

  compile.last = ""
  compile.stdout:read_start(compile.read)
  compile.stderr:read_start(compile.read)
end

function compile.open()
  if not compile.buffer then
    return false
  end

  local window = vim.fn.bufwinid(compile.buffer)
  if window == -1 then
    vim.cmd("split")
    vim.api.nvim_set_current_buf(compile.buffer)
  else
    vim.api.nvim_set_current_win(window)
  end

  return true
end

function compile.start(cmd)
  if not cmd or cmd == "" then
    _, cmd = pcall(vim.fn.input, "Compile: ")
    if cmd == "" then
      return
    end
  end

  if not compile.open() then
    vim.cmd("new")
    vim.api.nvim_win_set_option(0, "cursorline", true)

    compile.buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(compile.buffer, "*compilation*")
    vim.api.nvim_buf_set_option(compile.buffer, "buftype", "nofile")
    vim.api.nvim_buf_set_option(compile.buffer, "modifiable", false)

    vim.api.nvim_create_autocmd({"BufDelete"}, {
      buffer = compile.buffer,
      callback = function ()
        compile.buffer = nil
        compile.stop()
      end,
    })

    for key, func in pairs(compile.bindings) do
      vim.keymap.set("n", key, func, {buffer = compile.buffer, silent = true})
    end

    vim.cmd([[
      syntax match Label '^\f\+:'he=e-1
      syntax match Number "exit code \d\+$"hs=s+10
      syntax match Function '\%1l`.*`$'hs=s+1,he=e-1
      syntax match Underlined '\f\+:\d\+\(:\d\+\)\?'

      syntax keyword Function succeeded
      syntax keyword ErrorMsg error failed interrupted
      syntax keyword WarningMsg note hint warning
    ]])
  end

  compile.command = cmd
  compile.run()
end

function compile.this()
  if not compile.open() then
    compile.start()
    return
  end

  local pos = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(compile.buffer, pos[1] - 1, pos[1], false)[1]
    :sub(pos[2] + 1)

  if vim.fn.matchstr(line, "^\\f\\+:\\d\\+:") == "" then
    vim.cmd("normal! j")
    return
  end

  line = vim.split(line, ":")
  vim.cmd([[
    normal! zz
    wincmd p
    edit ]]..line[1])

  vim.api.nvim_win_set_cursor(0, {tonumber(line[2]) or 1, tonumber(line[3]) or 0})
end

function compile.next(prev)
  if compile.open() then
    vim.fn.search("\\f\\+:\\d\\+:\\(\\d\\+:\\)\\?", prev and "wb" or "w")
    compile.this()
  else
    compile.start()
  end
end

function compile.prev()
  compile.next(true)
end

function compile.restart()
  if compile.open() then
    compile.run()
  else
    compile.start()
  end
end

function compile.interrupt()
  if compile.open() then
    compile.stop()
    compile.line(-1, -1, {"Compilation interrupted"})
  else
    compile.start()
  end
end

function compile.bind(bindings)
  for key, func in pairs(bindings or {}) do
    compile.bindings[key] = func
  end
end

compile.bindings = {
  ["r"] = compile.restart,
  ["]e"] = compile.next,
  ["[e"] = compile.prev,
  ["<cr>"] = compile.this,
  ["<c-c>"] = compile.interrupt,
}

return compile
