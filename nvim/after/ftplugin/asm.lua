-- ARMv7-A big-endian assembly (GNU as)
-- Toolchain: arm-none-eabi-gcc (assembler + linker), qemu-armeb (runner), gdb (debugger)
local arm = require "configs.arm"

vim.bo.commentstring = "@ %s"
vim.bo.expandtab = false -- assembly traditionally uses tabs for column alignment
vim.bo.shiftwidth = 8
vim.bo.tabstop = 8
vim.bo.softtabstop = 8

local function term(cmd)
    vim.cmd "write"
    -- start the job directly: :terminal truncates commands over 1024 bytes (long paths)
    vim.cmd "botright 15new"
    if vim.fn.has "nvim-0.11" == 1 then
        vim.fn.jobstart({ "sh", "-c", cmd }, { term = true })
    else
        vim.fn.termopen { "sh", "-c", cmd }
    end
    vim.cmd "startinsert"
end

local function bin()
    local _, out = arm.paths()
    return out
end

local function run_cmd()
    return string.format('%s && %s; echo; echo "[exit code: $?]"', arm.build_cmd(), arm.qemu_cmd(bin(), nil, true))
end

-- plain gdb in a terminal (the UI debugger is <leader>ad / F5)
local function gdb_cmd()
    return string.format(
        "%s && { %s & %s; %s -q %s -ex 'target remote :%d' -ex 'layout regs'; }",
        arm.build_cmd(),
        arm.qemu_cmd(bin(), arm.GDB_PORT),
        arm.wait_for_qemu_cmd(),
        arm.GDB,
        vim.fn.shellescape(bin()),
        arm.GDB_PORT
    )
end

local function objdump_cmd()
    return string.format("%s && arm-none-eabi-objdump -d %s | less", arm.build_cmd(), vim.fn.shellescape(bin()))
end

-- every label with its address (hex), sorted by address, in a split sized to fit (q closes)
local function show_syms()
    vim.cmd "write"
    local res = vim.system(arm.build_argv(), { text = true }):wait()
    if res.code ~= 0 then
        vim.notify("Build failed:\n" .. res.stderr .. res.stdout, vim.log.levels.ERROR)
        return
    end
    res = vim.system({ "arm-none-eabi-nm", "-n", bin() }, { text = true }):wait()
    local lines = {}
    for _, line in ipairs(vim.split(res.stdout or "", "\n", { trimempty = true })) do
        local name = line:match "%S+$"
        -- skip linker-defined symbols (_end, __bss_start, _stack, ...)
        if name == "_start" or not name:match "^_" then
            table.insert(lines, line)
        end
    end

    vim.cmd("botright " .. math.min(math.max(#lines, 1), 30) .. "new")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.bo.modifiable = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = true, desc = "Close label addresses" })
end

vim.api.nvim_buf_create_user_command(0, "ArmBuild", function()
    term(arm.build_cmd())
end, { desc = "Build ARMv7 BE assembly" })
vim.api.nvim_buf_create_user_command(0, "ArmRun", function()
    term(run_cmd())
end, { desc = "Build and run in qemu-armeb" })
vim.api.nvim_buf_create_user_command(0, "ArmGdb", function()
    term(gdb_cmd())
end, { desc = "Build and debug with gdb in a terminal" })
vim.api.nvim_buf_create_user_command(0, "ArmDump", function()
    term(objdump_cmd())
end, { desc = "Build and disassemble" })
vim.api.nvim_buf_create_user_command(0, "ArmSyms", show_syms, { desc = "Build and list label addresses" })

local map = function(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = true, desc = desc })
end
map("<leader>ab", "<cmd>ArmBuild<cr>", "ARM build")
map("<leader>ar", "<cmd>ArmRun<cr>", "ARM run (qemu-armeb)")
map("<leader>ad", function()
    require("dap").continue()
end, "ARM debug (UI)")
map("<leader>ag", "<cmd>ArmGdb<cr>", "ARM debug (gdb terminal)")
map("<leader>ao", "<cmd>ArmDump<cr>", "ARM objdump")
map("<leader>as", "<cmd>ArmSyms<cr>", "ARM label addresses")
