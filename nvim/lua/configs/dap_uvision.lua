-- uVision-style debug windows for nvim-dap-ui:
-- Registers (R0..R15, CPSR flags, mode), Disassembly (mixed source / opcodes) and Memory (hex dump)
local dap = require "dap"
local M = {}

local ns = vim.api.nvim_create_namespace "arm_uvision"
local stop_id = 0 -- increments on every stop, used to detect changed values

---------------------------------------------------------------------------
-- Highlights
---------------------------------------------------------------------------
local function set_hl()
    local warn = vim.api.nvim_get_hl(0, { name = "DiagnosticWarn", link = false })
    local cursor = vim.api.nvim_get_hl(0, { name = "CursorLine", link = false })
    vim.api.nvim_set_hl(0, "ArmCurrentLine", { fg = warn.fg, bg = cursor.bg, bold = true })
    vim.api.nvim_set_hl(0, "ArmChanged", { link = "DiffText" })
    vim.api.nvim_set_hl(0, "ArmGroup", { link = "Title" })
    vim.api.nvim_set_hl(0, "ArmHeader", { link = "TabLineSel" })
    vim.api.nvim_set_hl(0, "ArmValue", { link = "Number" })
    vim.api.nvim_set_hl(0, "ArmSource", { link = "Comment" })
    vim.api.nvim_set_hl(0, "ArmAddr", { link = "Identifier" })
    vim.api.nvim_set_hl(0, "ArmOpcode", { link = "Constant" })
    vim.api.nvim_set_hl(0, "ArmMnemonic", { link = "Keyword" })
end
set_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })

---------------------------------------------------------------------------
-- Panel helper: a scratch buffer we fully redraw, with highlight ranges
---------------------------------------------------------------------------
local function panel(name, filetype)
    local p = {}
    function p.buffer()
        if not (p.buf and vim.api.nvim_buf_is_valid(p.buf)) then
            p.buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_name(p.buf, name)
            vim.bo[p.buf].filetype = filetype
            vim.bo[p.buf].modifiable = false
        end
        return p.buf
    end
    -- hls: { row, col_start, col_end (-1 = eol), group }
    function p.set(lines, hls, cursor_row)
        local flat = {}
        for _, l in ipairs(lines) do
            vim.list_extend(flat, vim.split(l, "\n", { plain = true }))
        end
        lines = flat
        vim.schedule(function()
            local buf = p.buffer()
            vim.bo[buf].modifiable = true
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            vim.bo[buf].modifiable = false
            vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
            for _, h in ipairs(hls or {}) do
                local row, s, e, group = unpack(h)
                if e == -1 then
                    vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { line_hl_group = group })
                else
                    vim.api.nvim_buf_set_extmark(buf, ns, row, s, { end_col = e, hl_group = group })
                end
            end
            if cursor_row then
                for _, win in ipairs(vim.fn.win_findbuf(buf)) do
                    vim.api.nvim_win_set_cursor(win, { cursor_row + 1, 0 })
                    vim.api.nvim_win_call(win, function()
                        vim.cmd "normal! zz"
                    end)
                end
            end
        end)
    end
    return p
end

local function current()
    local s = dap.session()
    return s, s and s.current_frame
end

local function to_u32(str)
    local n = tonumber(str and (str:match "^%-?0x%x+" or str:match "^%-?%d+") or nil)
    if n and n < 0 then
        n = n + 2 ^ 32
    end
    return n
end

---------------------------------------------------------------------------
-- Registers
---------------------------------------------------------------------------
local regs = panel("Registers", "dapui_registers")
local reg_state = { cur = {}, prev = {}, stop = -1 }

local REG_ROWS = {
    { "r0", "R0" }, { "r1", "R1" }, { "r2", "R2" }, { "r3", "R3" },
    { "r4", "R4" }, { "r5", "R5" }, { "r6", "R6" }, { "r7", "R7" },
    { "r8", "R8" }, { "r9", "R9" }, { "r10", "R10" }, { "r11", "R11" },
    { "r12", "R12" }, { "sp", "R13 (SP)" }, { "lr", "R14 (LR)" }, { "pc", "R15 (PC)" },
}
local MODES = {
    [0x10] = "User", [0x11] = "FIQ", [0x12] = "IRQ", [0x13] = "Supervisor", [0x16] = "Monitor",
    [0x17] = "Abort", [0x1A] = "Hyp", [0x1B] = "Undefined", [0x1F] = "System",
}
local FLAGS = { { "N", 31 }, { "Z", 30 }, { "C", 29 }, { "V", 28 }, { "Q", 27 }, { "J", 24 }, { "E", 9 }, { "A", 8 }, { "I", 7 }, { "F", 6 }, { "T", 5 } }

local function bit(v, n)
    return math.floor(v / 2 ^ n) % 2
end

local function draw_registers(vals)
    local lines, hls = { " Register        Value" }, { { 0, 0, -1, "ArmHeader" } }
    local function add(text, value_col, changed)
        table.insert(lines, text)
        local row = #lines - 1
        if value_col then
            table.insert(hls, { row, value_col, #text, changed and "ArmChanged" or "ArmValue" })
        end
    end
    local function group(title)
        table.insert(lines, title)
        table.insert(hls, { #lines - 1, 0, #title, "ArmGroup" })
    end
    local function changed(name)
        return reg_state.prev[name] ~= nil and reg_state.prev[name] ~= vals[name]
    end

    group " ▾ Current"
    for _, r in ipairs(REG_ROWS) do
        local v = vals[r[1]]
        if v then
            add(("     %-11s 0x%08X"):format(r[2], v), 17, changed(r[1]))
        end
    end
    local cpsr = vals.cpsr
    if cpsr then
        add(("   ▾ %-11s 0x%08X"):format("CPSR", cpsr), 17, changed "cpsr")
        local prev = reg_state.prev.cpsr
        for _, f in ipairs(FLAGS) do
            local b = bit(cpsr, f[2])
            add(("       %-9s %d"):format(f[1], b), 17, prev and bit(prev, f[2]) ~= b)
        end
        add(("       %-9s 0x%02X"):format("M", cpsr % 32), 17, prev and prev % 32 ~= cpsr % 32)
    end
    group " ▾ Internal"
    if vals.pc then
        add(("     %-11s 0x%08X"):format("PC $", vals.pc), 17, changed "pc")
    end
    if cpsr then
        add(("     %-11s %s"):format("Mode", MODES[cpsr % 32] or "?"), 17)
        add(("     %-11s %s"):format("State", bit(cpsr, 5) == 1 and "Thumb" or "ARM"), 17)
    end
    add(("     %-11s %s"):format("Endian", "Big (BE8)"), 17)
    regs.set(lines, hls)
end

function M.render_registers()
    local s, f = current()
    if not f then
        return regs.set { " Register        Value", "", " (not debugging)" }
    end
    s:request("scopes", { frameId = f.id }, function(err, resp)
        local scope
        for _, sc in ipairs((not err and resp and resp.scopes) or {}) do
            if sc.name == "Registers" then
                scope = sc
            end
        end
        if not scope then
            return
        end
        s:request("variables", { variablesReference = scope.variablesReference }, function(err2, r2)
            if err2 or not r2 then
                return
            end
            local vals = {}
            for _, v in ipairs(r2.variables) do
                vals[v.name] = to_u32(v.value)
            end
            if reg_state.stop ~= stop_id then -- new stop: remember last values for change highlighting
                reg_state.prev, reg_state.cur, reg_state.stop = reg_state.cur, vals, stop_id
            end
            draw_registers(vals)
        end)
    end)
end

---------------------------------------------------------------------------
-- Disassembly (mixed source / instructions, like uVision)
---------------------------------------------------------------------------
local disasm = panel("Disassembly", "dapui_disassembly")
local BEFORE, AFTER = 12, 24
local src_cache = {}

local function source_line(path, line)
    if not path then
        return nil
    end
    if not src_cache[path] then
        src_cache[path] = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
    end
    return src_cache[path][line]
end

-- gdb gives memory byte order; BE8 code is stored little endian, so reverse to get the opcode word
local function opcode(bytes)
    if not bytes then
        return ""
    end
    local out = {}
    for b in bytes:gmatch "%x%x" do
        table.insert(out, 1, b)
    end
    return table.concat(out):upper()
end

local function fmt_operands(ops)
    ops = ops:gsub("%s*[@;].*$", "") -- drop gdb's trailing comments
    -- immediates in hex like uVision, except shift amounts (LSL #4)
    ops = ops:gsub("(%a*)(%s*)#(%-?%d+)%f[^%w]", function(prefix, sp, n)
        local shift = prefix:lower():match "^[la]s[lr]$" or prefix:lower() == "ror"
        return prefix:upper() .. sp .. (shift and "#" .. n or ("#0x%08X"):format(to_u32(n)))
    end)
    ops = ops:gsub("%f[%w_]([rR]%d%d?)%f[^%w_]", string.upper)
    for _, r in ipairs { "sp", "lr", "pc", "fp", "ip", "sl", "sb" } do
        ops = ops:gsub("%f[%w_]" .. r .. "%f[^%w_]", r:upper())
    end
    return ops
end

local function draw_disasm(instrs, pc)
    local lines, hls, cur_row = {}, {}, nil
    local last_line
    for _, ins in ipairs(instrs) do
        local path = ins.location and ins.location.path
        if ins.line and ins.line ~= last_line then
            local text = source_line(path, ins.line)
            if text then
                table.insert(lines, ("%8d:  %s"):format(ins.line, vim.trim(text):gsub("\t", " ")))
                table.insert(hls, { #lines - 1, 0, -1, "ArmSource" })
            end
            last_line = ins.line
        end
        local addr = tonumber(ins.address)
        local mnem, ops = (ins.instruction or ""):match "^(%S+)%s*(.*)$"
        local is_pc = addr == pc
        local line = ("%s0x%08X  %-8s  %-7s %s"):format(
            is_pc and "➔" or " ",
            addr or 0,
            opcode(ins.instructionBytes),
            (mnem or ""):upper(),
            fmt_operands(ops or "")
        )
        table.insert(lines, line)
        local row = #lines - 1
        if is_pc then
            cur_row = row
            table.insert(hls, { row, 0, -1, "ArmCurrentLine" })
        else
            local a = #" 0x00000000"
            table.insert(hls, { row, 1, a, "ArmAddr" })
            table.insert(hls, { row, a + 2, a + 10, "ArmOpcode" })
            table.insert(hls, { row, a + 12, a + 19, "ArmMnemonic" })
        end
    end
    disasm.set(lines, hls, cur_row)
end

function M.render_disassembly()
    local s, f = current()
    local pc = f and to_u32(f.instructionPointerReference)
    if not pc then
        return disasm.set { " (not debugging)" }
    end
    -- gdb can't disassemble backwards, but ARM instructions are 4 bytes:
    -- start BEFORE instructions earlier, backing off if that memory isn't mapped
    local function try(back)
        s:request("disassemble", {
            memoryReference = ("0x%x"):format(pc - 4 * back),
            instructionCount = back + AFTER,
            resolveSymbols = true,
        }, function(err, resp)
            if err or not resp then
                if back > 0 then
                    return try(math.floor(back / 2))
                end
                return disasm.set { " " .. tostring(err and err.message or "no disassembly") }
            end
            draw_disasm(resp.instructions, pc)
        end)
    end
    try(BEFORE)
end

---------------------------------------------------------------------------
-- Memory (hex + ASCII, 16 bytes per row)
---------------------------------------------------------------------------
local memory = panel("Memory 1", "dapui_memory")
local mem = { expr = nil, count = 128, prev = {}, cur = {}, stop = -1 }

local function draw_memory(addr, data)
    local lines, hls = { (" Address: %s"):format(mem.expr) }, { { 0, 0, -1, "ArmHeader" } }
    if mem.stop ~= stop_id then
        mem.prev, mem.cur, mem.stop = mem.cur, {}, stop_id
    end
    for off = 0, #data - 1, 16 do
        local row_addr = addr + off
        local hex, ascii, changed = {}, {}, {}
        for i = 0, 15 do
            local b = data:byte(off + i + 1)
            if b then
                mem.cur[row_addr + i] = b
                local old = mem.prev[row_addr + i]
                if old and old ~= b then
                    table.insert(changed, i)
                end
                table.insert(hex, ("%02X"):format(b))
                table.insert(ascii, (b >= 32 and b < 127) and string.char(b) or ".")
            end
        end
        local line = ("0x%08X: %-47s  %s"):format(row_addr, table.concat(hex, " "), table.concat(ascii))
        table.insert(lines, line)
        local row = #lines - 1
        table.insert(hls, { row, 0, 11, "ArmAddr" })
        for _, i in ipairs(changed) do
            table.insert(hls, { row, 12 + i * 3, 14 + i * 3, "ArmChanged" })
        end
    end
    memory.set(lines, hls)
end

function M.render_memory()
    if not mem.expr then
        return memory.set {
            " No address set.",
            " <leader>dm  or  :ArmMem <addr|&label|$reg> [bytes]",
            "   e.g. :ArmMem &nums     :ArmMem $sp 64",
        }
    end
    local s, f = current()
    if not f then
        return memory.set { (" Address: %s  (not debugging)"):format(mem.expr) }
    end
    local expr = ("(unsigned int)(%s)"):format(mem.expr)
    s:request("evaluate", { expression = expr, context = "watch", frameId = f.id }, function(err, r)
        local addr = not err and r and to_u32(r.result)
        if not addr then
            return memory.set { (" Address: %s"):format(mem.expr), " " .. tostring(err and err.message or "bad address") }
        end
        s:request("readMemory", { memoryReference = ("0x%x"):format(addr), count = mem.count }, function(err2, r2)
            if err2 or not r2 or not r2.data then
                return memory.set { (" Address: %s"):format(mem.expr), " " .. tostring(err2 and err2.message or "unreadable") }
            end
            draw_memory(to_u32(r2.address) or addr, vim.base64.decode(r2.data))
        end)
    end)
end

function M.set_memory(expr, count)
    mem.expr = expr
    mem.count = count or mem.count
    M.render_memory()
end

function M.memory_expr()
    return mem.expr
end

---------------------------------------------------------------------------
-- Refresh + window titles
---------------------------------------------------------------------------
function M.render_all()
    M.render_registers()
    M.render_disassembly()
    M.render_memory()
end

local TITLES = {
    dapui_registers = "Registers",
    dapui_disassembly = "Disassembly",
    dapui_memory = "Memory 1",
    ["dap-repl"] = "Command",
    dapui_watches = "Watch 1",
    dapui_stacks = "Call Stack",
    dapui_breakpoints = "Breakpoints",
}

function M.set_titles()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local title = TITLES[vim.bo[vim.api.nvim_win_get_buf(win)].filetype]
        if title then
            vim.wo[win].winbar = "%#ArmHeader# " .. title .. " %*"
        end
    end
end

dap.listeners.after.event_stopped.arm_uvision = function()
    stop_id = stop_id + 1
    -- current_frame is filled in by the stackTrace that follows a stop
    vim.defer_fn(M.render_all, 150)
end
dap.listeners.after.event_terminated.arm_uvision = function()
    vim.defer_fn(M.render_all, 50)
end

function M.register(dapui)
    dapui.register_element("registers", { render = M.render_registers, buffer = regs.buffer, allow_without_session = true })
    dapui.register_element("disassembly", { render = M.render_disassembly, buffer = disasm.buffer, allow_without_session = true })
    dapui.register_element("memory", {
        render = M.render_memory,
        buffer = memory.buffer,
        allow_without_session = true,
        float_defaults = function()
            return { width = 80, height = 12 }
        end,
    })
end

return M
