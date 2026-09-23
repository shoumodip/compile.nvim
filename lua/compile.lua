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

function M.start(cmd)
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

    vim.cmd.terminal(cmd)
    vim.api.nvim_win_set_option(0, "cursorline", true)

    vim.api.nvim_win_set_option(0, "number", number_before)
    vim.api.nvim_win_set_option(0, "relativenumber", relativenumber_before)

    M.cmd = cmd
    M.buffer = vim.api.nvim_get_current_buf()
    if previous then
        vim.api.nvim_buf_delete(previous, {force = true})
    end

    vim.b[M.buffer].compile_nvim_cmd    = cmd
    vim.b[M.buffer].compile_nvim_active = true
    vim.b[M.buffer].compile_nvim_status = 0

    vim.api.nvim_buf_set_name(M.buffer, "*compilation*")
    vim.api.nvim_buf_set_option(M.buffer, "filetype", "compilation")

    for key, func in pairs(bindings) do
        vim.keymap.set("n", key, func, {buffer = M.buffer, silent = false})
    end

    vim.api.nvim_create_autocmd("TermClose", {
        buf = M.buffer,
        callback = function(ev)
            local duration = (vim.uv.hrtime() - start) / 1e9

            local message = {{"Compilation "}}
            if vim.bo[ev.buf].channel == 0 then
                table.insert(message, {"exited abnormally", "DiagnosticError"})
                vim.b[M.buffer].compile_nvim_status = 1
            else
                if vim.v.event.status == 0 then
                    table.insert(message, {"finished", "DiagnosticOk"})
                    vim.b[M.buffer].compile_nvim_status = 0
                else
                    table.insert(message, {"exited abnormally", "DiagnosticError"})
                    table.insert(message, {" with code "})
                    table.insert(message, {tostring(vim.v.event.status), "DiagnosticError"})
                    vim.b[M.buffer].compile_nvim_status = vim.v.event.status
                end
            end

            local hours = math.floor(duration / 3600)
            local minutes = math.floor((duration % 3600) / 60)
            local seconds = duration % 60

            local duration = ""
            if hours > 0 then
                duration = string.format("%s%dh", duration, hours)
            end

            if minutes > 0 or (hours > 0 and seconds > 0) then
                duration = string.format("%s %dm", duration, minutes)
            end

            if seconds > 0 then
                duration = string.format("%s %.2fs", duration, seconds)
            end

            table.insert(message, {string.format(" in %s", vim.trim(duration))})
            if M.notify then
                vim.api.nvim_echo(message, false, {})
            end

            local ns = vim.api.nvim_get_namespaces()["nvim.terminal.exitmsg"]
            for _, it in ipairs(vim.api.nvim_buf_get_extmarks(M.buffer, ns, 0, -1, {})) do
                vim.api.nvim_buf_del_extmark(M.buffer, ns, it[1])
            end

            vim.b[M.buffer].compile_nvim_active   = false
            vim.b[M.buffer].compile_nvim_duration = duration
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
    M.notify = opts.notify
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
        notify = true,

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
