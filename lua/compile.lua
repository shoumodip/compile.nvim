local M = {}

local pattern = {}  -- The currently active pattern
local patterns = {} -- All the registered patterns
local bindings = {} -- The bindings

local function is_open()
    if not M.buffer then
        return false
    end

    if not vim.api.nvim_buf_is_valid(M.buffer) then
        M.buffer = nil
        return false
    end

    return true
end

local function open()
    if not is_open() then
        return false
    end

    local window = vim.fn.bufwinid(M.buffer)
    if window == -1 then
        vim.cmd("split")
        vim.api.nvim_set_current_buf(M.buffer)
    else
        vim.api.nvim_set_current_win(window)
    end

    return true
end

local function apply_highlights()
    if not is_open() then
        return
    end

    local function escape(s)
        return s:gsub("/", "\\/")
    end

    vim.api.nvim_buf_call(M.buffer, function ()
        vim.cmd(string.format([[
            syntax clear
            syntax match String '\%%1l`.*`$'
            syntax match Underlined /%s/
        ]], escape(pattern[1])))
    end)
end

local function compile_driver_if_needed()
    local root   = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
    local source = root.."/driver/driver.c"
    local binary = root.."/driver/driver.exe"

    local source_stat = vim.uv.fs_stat(source)
    local binary_stat = vim.uv.fs_stat(binary)
    if binary_stat and not (
        source_stat.mtime.sec > binary_stat.mtime.sec
        or (
            source_stat.mtime.sec == binary_stat.mtime.sec
            and source_stat.mtime.nsec > binary_stat.mtime.nsec
        )
    ) then return binary end

    vim.notify("[compile.nvim] Compiling driver", vim.log.levels.INFO)
    local result
    if vim.fn.has("win32") == 1 then
        result = vim.system({"cl.exe", "/nologo", "/Fe:"..binary, source}):wait()
    else
        result = vim.system({"cc", "-o", binary, source, "-lm"}):wait()
    end

    if result.code ~= 0 then
        vim.notify(
            "[compile.nvim] Failed to compile driver. Make sure a C SDK is available, or compile it manually:\n"..
            "\n"..
            "    $ cd "..root.."\n"..
            "    $ cc -o driver/driver.exe driver/driver.c -lm  # If on Linux/macOS\n"..
            "    $ cl.exe /Fe:driver/driver.exe driver/driver.c # If on Windows\n"
            , vim.log.levels.ERROR)
        return null
    end
    return binary
end

function M.start(cmd)
    local binary = compile_driver_if_needed()
    if not binary then
        return
    end

    if not cmd or cmd == "" then
        vim.cmd("echohl Question")
        _, cmd = pcall(vim.fn.input, "Compile: ", "", "shellcmdline")
        vim.cmd("echohl Normal | mode")
        if cmd == "" then
            return
        end
    end

    local previous = nil
    if is_open() then
        local window = vim.fn.bufwinid(M.buffer)
        if window == -1 then
            vim.api.nvim_buf_delete(M.buffer, {force = true})
        else
            previous = M.buffer
            vim.api.nvim_set_current_win(window)
        end
    end

    local number_before = vim.api.nvim_win_get_option(0, "number")
    local relativenumber_before = vim.api.nvim_win_get_option(0, "relativenumber")
    local start = vim.uv.hrtime()

    vim.cmd("wall")
    if not previous then
        vim.cmd("split")
    end

    M.cmd = cmd
    M.buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(M.buffer)

    vim.fn.jobstart({binary, M.cmd}, {term = true})
    vim.api.nvim_win_set_option(0, "cursorline", true)
    vim.api.nvim_win_set_option(0, "number", number_before)
    vim.api.nvim_win_set_option(0, "relativenumber", relativenumber_before)
    if previous then
        vim.api.nvim_buf_delete(previous, {force = true})
    end
    vim.api.nvim_buf_set_name(M.buffer, "*compilation*")
    vim.api.nvim_buf_set_option(M.buffer, "filetype", "compilation")

    for key, func in pairs(bindings) do
        vim.keymap.set("n", key, func, {buffer = M.buffer, silent = false})
    end

    vim.api.nvim_create_autocmd("TermClose", {
        buf = M.buffer,
        callback = function(ev)
            local ns = vim.api.nvim_get_namespaces()["nvim.terminal.exitmsg"]
            for _, it in ipairs(vim.api.nvim_buf_get_extmarks(M.buffer, ns, 0, -1, {})) do
                vim.api.nvim_buf_del_extmark(M.buffer, ns, it[1])
            end

            local row   = ev.data.pos
            local lines = vim.api.nvim_buf_get_lines(M.buffer, ev.data.pos - 2, ev.data.pos, false)
            if lines[2] == "" then
                row = row - 1
            end

            vim.api.nvim_buf_call(M.buffer, function ()
                vim.cmd(string.format([[
                    syntax match DiagnosticOk    '\%%%dl\<finished\>'
                    syntax match DiagnosticError '\%%%dl\<exited abnormally\>'
                    syntax match DiagnosticError '\%%%dl\<code \d\+'hs=s+5
                ]], row, row, row))
            end)
        end
    })

    apply_highlights()
end

local function edit_file(path)
    local fullpath = vim.fn.fnamemodify(path, ":p")
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            if vim.fn.fnamemodify(bufname, ":p") == fullpath then
                vim.api.nvim_set_current_buf(bufnr)
                return
            end
        end
    end

    vim.cmd.edit(fullpath)
end

function M.open()
    if not open() then
        M.start()
        return
    end

    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()

    local cursor = 0
    local result = {}
    while true do
        local match_text, match_begin, match_end = unpack(vim.fn.matchstrpos(line, pattern[1], cursor))
        if match_begin == -1 then
            return
        end

        if col >= match_begin and col < match_end then
            local list = vim.fn.matchlist(match_text, pattern[1])
            if #vim.tbl_keys(pattern) == 1 then
                table.insert(result, list[2])
                table.insert(result, list[3])
                table.insert(result, list[4])
            else
                table.insert(result, list[1 + pattern.path])
                table.insert(result, list[1 + pattern.row])
                table.insert(result, list[1 + pattern.col])
            end
            break
        end

        cursor = match_end
    end

    local path = result[1]
    local row  = result[2] == "" and 1 or tonumber(result[2])
    local col  = (result[3] == "" and 1 or tonumber(result[3])) - 1

    vim.cmd([[
        normal! zz
        wincmd p
    ]])

    edit_file(path)
    if row == vim.fn.line("$") + 1 then
        row = row - 1
        col = #vim.fn.getline("$") - 1
    end

    pcall(vim.api.nvim_win_set_cursor, 0, {row, col})
    vim.cmd("normal! zz")
end

function M.open_mouse_click()
    local mouse = vim.fn.getmousepos()
    vim.api.nvim_set_current_win(mouse.winid)
    vim.api.nvim_win_set_cursor(mouse.winid, { mouse.line, math.max(mouse.column - 1, 0) })
    M.open()
end

function M.next()
    if not open() then
        M.start()
        return
    end

    vim.fn.search(pattern[1], "w")
    M.open()
end

function M.prev()
    if not open() then
        M.start()
        return
    end

    vim.fn.search(pattern[1], "wb")
    M.open()
end

function M.restart()
    M.start(M.cmd)
end

function M.stop()
    if is_open() then
        vim.fn.jobstop(vim.b[M.buffer].terminal_job_id)
    end
end

function M.pattern(name)
    if not name then
        local current = vim.api.nvim_get_current_win()
        vim.cmd("wincmd p")

        local previous = vim.api.nvim_get_current_win()
        vim.cmd("wincmd p")

        local names = vim.tbl_keys(patterns)
        for i, name in ipairs(names) do
            if patterns[name] == pattern then
                table.insert(names, 1, table.remove(names, i))
                break
            end
        end

        return vim.ui.select(names, {prompt = "Select Pattern"}, function (p)
            vim.api.nvim_set_current_win(previous)
            vim.api.nvim_set_current_win(current)
            M.pattern(p)
        end)
    end

    local p = patterns[name]
    if not p then
        return
    end

    pattern = p
    apply_highlights()
end

function M.bind(bs)
    for key, func in pairs(bs or {}) do
        bindings[key] = func
    end
end

function M.setup(opts)
    M.bind(opts.bindings)
    for name, pattern in pairs(opts.patterns or {}) do
        if type(pattern) == "string" then
            pattern = {pattern}
        end

        if type(pattern) ~= "table" then
            error("Expected pattern to be string or table, got "..type(pattern))
        end

        for key, value in pairs(pattern) do
            local expected = nil
            if key == 1 then
                expected = "string"
            elseif key == "path" or key == "row" or key == "col" then
                expected = "number"
            else
                error("Invalid key '"..key.."' in pattern")
            end

            local actual = type(value)
            if actual ~= expected then
                error("Expected key '"..key.."' of pattern to be "..expected..", got "..actual)
            end
        end

        if not pattern[1] then
            error("The pattern string is missing")
        end

        if #vim.tbl_keys(pattern) ~= 1 then
            if not pattern.path then
                error("The pattern path is missing")
            end

            if not pattern.row then
                error("The pattern row is missing")
            end
        end

        patterns[name] = pattern
    end
end

do
    M.setup {
        bindings = {
            ["s"] = M.pattern,
            ["r"] = M.restart,
            ["]e"] = M.next,
            ["[e"] = M.prev,
            ["<cr>"] = M.open,
            ["<c-c>"] = M.stop,
            ["<leftmouse>"] = M.open_mouse_click,
        },

        patterns = {
            Default = [[\(\f\+\):\(\d\+\):\(\d\+\)]]
        }
    }

    pattern = patterns.Default
end

return M
