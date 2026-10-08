-- uVision-style debugger for ARMv7 big-endian assembly
-- gdb (native DAP mode) attached to qemu-armeb's gdb stub
local dap = require "dap"
local dapui = require "dapui"
local arm = require "configs.arm"

local qemu -- running qemu-armeb process

local function stop_qemu()
    if qemu then
        qemu:kill "sigterm"
        qemu = nil
    end
end

-- ask the OS for an unused TCP port so sessions never clash on a fixed one
local function free_port()
    local tcp = vim.uv.new_tcp()
    tcp:bind("127.0.0.1", 0)
    local port = tcp:getsockname().port
    tcp:close()
    return port
end

-- Build the current file and start it paused in qemu, waiting for gdb.
local function build_and_launch(config, on_config)
    vim.cmd "silent! write"
    local res = vim.system(arm.build_argv(), { text = true }):wait()
    if res.code ~= 0 then
        vim.notify("Build failed:\n" .. res.stderr .. res.stdout, vim.log.levels.ERROR)
        return
    end

    local _, bin = arm.paths()
    local port = free_port()
    stop_qemu()
    local function to_repl(_, data)
        if data then
            vim.schedule(function()
                dap.repl.append(data)
            end)
        end
    end
    qemu = vim.system({ "qemu-armeb", "-g", tostring(port), bin }, { stdout = to_repl, stderr = to_repl })
    vim.wait(300) -- let qemu open the gdb port

    on_config(vim.tbl_extend("force", config, { program = bin, target = "localhost:" .. port }))
end

dap.adapters.gdb = {
    type = "executable",
    command = "gdb",
    -- output-radix 16: show registers, watches and prints in hex (like uVision)
    args = { "-q", "-i", "dap", "-ex", "set output-radix 16" },
    enrich_config = build_and_launch,
}

dap.configurations.asm = {
    {
        name = "ARMv7 BE (qemu-armeb)",
        type = "gdb",
        request = "attach",
    },
}

dap.listeners.after.event_terminated.arm = stop_qemu
dap.listeners.after.event_exited.arm = stop_qemu
dap.listeners.after.disconnect.arm = stop_qemu

---------------------------------------------------------------------------
-- uVision layout:
--   left: Registers | top: Disassembly | center: source
--   bottom: Command | Memory 1 | Watch 1 / Call Stack
---------------------------------------------------------------------------
local uv = require "configs.dap_uvision"

dapui.setup {
    layouts = {
        {
            position = "left",
            size = 34,
            elements = { { id = "registers", size = 1 } },
        },
        {
            position = "top",
            size = 12,
            elements = { { id = "disassembly", size = 1 } },
        },
        {
            position = "bottom",
            size = 12,
            elements = {
                { id = "repl", size = 0.4 },
                { id = "memory", size = 0.4 },
                { id = "watches", size = 0.2 },
            },
        },
    },
    controls = { enabled = false },
    render = { indent = 2 },
}
uv.register(dapui)

local function ui_open()
    dapui.open { reset = true }
    vim.schedule(uv.set_titles)
end

vim.api.nvim_create_user_command("ArmMem", function(opts)
    uv.set_memory(opts.fargs[1], tonumber(opts.fargs[2]))
end, { nargs = "+", desc = "Memory window: :ArmMem <addr|&label|$reg> [bytes]" })

dap.listeners.after.event_initialized.dapui = ui_open
dap.listeners.before.event_terminated.dapui = function()
    dapui.close()
end
dap.listeners.before.event_exited.dapui = function()
    dapui.close()
end

vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
vim.fn.sign_define("DapStopped", { text = "➔", texthl = "DiagnosticWarn", linehl = "ArmCurrentLine" })

---------------------------------------------------------------------------
-- Keys (uVision defaults: F5 run, F9 breakpoint, F10 step over, F11 step)
---------------------------------------------------------------------------
local instr = { steppingGranularity = "instruction" }
local map = vim.keymap.set

map("n", "<F5>", dap.continue, { desc = "Debug start / run" })
map("n", "<F9>", dap.toggle_breakpoint, { desc = "Debug toggle breakpoint" })
map("n", "<F10>", function()
    dap.step_over(instr)
end, { desc = "Debug step over" })
map("n", "<F11>", function()
    dap.step_into(instr)
end, { desc = "Debug step" })
map("n", "<S-F11>", dap.step_out, { desc = "Debug step out" })
map("n", "<leader>dq", function()
    dap.terminate()
    stop_qemu()
    dapui.close()
end, { desc = "Debug stop" })
map("n", "<leader>dc", dap.run_to_cursor, { desc = "Debug run to cursor" })
map("n", "<leader>du", function()
    dapui.toggle { reset = true }
    vim.schedule(uv.set_titles)
end, { desc = "Debug toggle UI" })
map({ "n", "v" }, "<leader>de", dapui.eval, { desc = "Debug evaluate" })
map("n", "<leader>dw", function()
    vim.ui.input({ prompt = "Watch: " }, function(expr)
        if expr and expr ~= "" then
            dapui.elements.watches.add(expr)
        end
    end)
end, { desc = "Debug add watch" })
map("n", "<leader>dm", function()
    vim.ui.input({ prompt = "Memory address: ", default = uv.memory_expr() }, function(expr)
        if expr and expr ~= "" then
            uv.set_memory(expr)
        end
    end)
end, { desc = "Debug memory address" })
