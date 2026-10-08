-- Shared ARMv7-A big-endian toolchain settings (used by ftplugin/asm and the debugger)
local M = {}

M.CC = "arm-none-eabi-gcc"
M.CFLAGS = { "-march=armv7-a", "-marm", "-mbig-endian", "-nostdlib", "-static", "-g", "-Wl,--be8" }
M.GDB_PORT = 1234

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

-- build command as a shell string (for :terminal)
function M.build_cmd()
    return table.concat(vim.tbl_map(vim.fn.shellescape, M.build_argv()), " ")
end

return M
