-- Shared ARMv7-A big-endian toolchain settings (used by ftplugin/asm and the debugger)
local M = {}

M.CC = "arm-none-eabi-gcc"
-- -Ttext=0: code starts at address 0 like Keil uVision, so label addresses match it
M.CFLAGS = { "-march=armv7-a", "-marm", "-mbig-endian", "-nostdlib", "-static", "-g", "-Wl,--be8", "-Wl,-Ttext=0" }
M.GDB_PORT = 1234

-- macOS has no qemu user-mode emulation, so qemu-armeb runs in a Linux container
-- (Docker Desktop, OrbStack or colima) and gdb is Homebrew's arm-none-eabi-gdb
M.is_mac = vim.uv.os_uname().sysname == "Darwin"
M.GDB = M.is_mac and "arm-none-eabi-gdb" or "gdb"
M.QEMU_IMAGE = "nvim-qemu-armeb"
M.CONTAINER = "nvim-qemu-armeb"
M.DOCKERFILE = [[
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends qemu-user && rm -rf /var/lib/apt/lists/*
]]

function M.has_makefile()
    return vim.fn.filereadable "Makefile" == 1 or vim.fn.filereadable "makefile" == 1
end

-- source file and output binary for the current buffer
function M.paths()
    return vim.fn.expand "%:p", vim.fn.expand "%:p:r"
end

-- build command as a list (for vim.system)
function M.build_argv()
    if M.has_makefile() then
        return { "make" }
    end
    local src, out = M.paths()
    local argv = { M.CC }
    vim.list_extend(argv, M.CFLAGS)
    vim.list_extend(argv, { src, "-o", out })
    return argv
end

local function shell(argv)
    return table.concat(vim.tbl_map(vim.fn.shellescape, argv), " ")
end

-- build command as a shell string (for :terminal)
function M.build_cmd()
    return shell(M.build_argv())
end

-- qemu-armeb command as a list; with port it waits for gdb, tty attaches the terminal (macOS)
function M.qemu_argv(bin, port, tty)
    local qemu = { "qemu-armeb" }
    if port then
        vim.list_extend(qemu, { "-g", tostring(port) })
    end
    table.insert(qemu, bin)
    if not M.is_mac then
        return qemu
    end

    local dir = vim.fs.dirname(bin)
    local argv = { "docker", "run", "--rm", "--init", "--name", M.CONTAINER, "-v", dir .. ":" .. dir, "-w", dir }
    if tty then
        table.insert(argv, "-it")
    end
    if port then
        vim.list_extend(argv, { "-p", string.format("127.0.0.1:%d:%d", port, port) })
    end
    table.insert(argv, M.QEMU_IMAGE)
    return vim.list_extend(argv, qemu)
end

-- qemu-armeb command as a shell string (for :terminal)
function M.qemu_cmd(bin, port, tty)
    return shell(M.qemu_argv(bin, port, tty))
end

-- block until qemu's gdb stub can accept a connection; false if the container never came up
function M.wait_for_qemu(proc)
    if not M.is_mac then
        vim.wait(300)
        return true
    end
    -- docker's port proxy accepts before qemu listens, so wait for the container instead
    local running = false
    vim.wait(10000, function()
        if proc and proc:is_closing() then
            return true -- docker run already exited: the container failed to start
        end
        local res = vim.system({ "docker", "inspect", "-f", "{{.State.Running}}", M.CONTAINER }, { text = true })
            :wait()
        running = vim.trim(res.stdout or "") == "true"
        return running
    end, 100)
    vim.wait(300)
    return running
end

-- shell snippet that does the same, for :terminal commands
function M.wait_for_qemu_cmd()
    if not M.is_mac then
        return "sleep 0.3"
    end
    return string.format(
        "until [ \"$(docker inspect -f '{{.State.Running}}' %s 2>/dev/null)\" = true ]; do sleep 0.1; done; sleep 0.3",
        M.CONTAINER
    )
end

-- remove a container left behind by a killed session (no-op on Linux)
function M.cleanup()
    if M.is_mac then
        vim.system({ "docker", "rm", "-f", M.CONTAINER }):wait()
    end
end

-- macOS: build the qemu-armeb container image (once)
function M.setup()
    if not M.is_mac then
        vim.notify "ArmSetup is only needed on macOS"
        return
    end
    vim.notify("Building " .. M.QEMU_IMAGE .. " image...")
    vim.system({ "docker", "build", "-t", M.QEMU_IMAGE, "-" }, { stdin = M.DOCKERFILE, text = true }, function(res)
        vim.schedule(function()
            if res.code == 0 then
                vim.notify(M.QEMU_IMAGE .. " image ready")
            else
                vim.notify("docker build failed:\n" .. res.stderr, vim.log.levels.ERROR)
            end
        end)
    end)
end

vim.api.nvim_create_user_command("ArmSetup", M.setup, { desc = "macOS: build the qemu-armeb Docker image" })

return M
