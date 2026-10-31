# Neovim config

NvChad v2.5 based setup for C/C++, Lua, LaTeX and **ARMv7-A big-endian assembly**
(GNU `as` syntax, run in `qemu-armeb`, debugged with a uVision-style UI).

`<leader>` is **Space**. Press `<leader>wK` (or `<leader>ch`) inside Neovim to search every keymap.

## Contents

- [Requirements](#requirements)
- [ARM assembly](#arm-assembly)
- [Debugger](#debugger)
- [Snippets](#snippets)
- [General keys](#general-keys)
- [LSP, formatting, linting](#lsp-formatting-linting)
- [LaTeX](#latex)
- [Troubleshooting](#troubleshooting)

## Requirements

| | Linux | macOS |
|---|---|---|
| Assembler/linker | `arm-none-eabi-gcc` | `brew install arm-none-eabi-gcc` |
| Runner | `qemu-armeb` (package `qemu-user`) | Docker via Colima: `brew install colima docker` |
| Debugger | `gdb` ≥ 14 with Python | `brew install arm-none-eabi-gdb` |

macOS has no `qemu-armeb`, so it runs inside a container. One-time setup:

```sh
colima start                 # after every reboot, or: brew services start colima
```

Then run `:ArmSetup` once in Neovim to build the `nvim-qemu-armeb` image.

## ARM assembly

These work in any `.s` file. Each one saves the file and builds it first. If the
folder has a `Makefile`, `make` is used instead of the built-in compile command.

| Key | Command | What it does |
|---|---|---|
| `<leader>ab` | `:ArmBuild` | Build only |
| `<leader>ar` | `:ArmRun` | Build and run in `qemu-armeb`, shows the exit code |
| `<leader>ad` | | Build and start the debugger UI (same as `F5`) |
| `<leader>ag` | `:ArmGdb` | Build and debug with plain `gdb` in a terminal |
| `<leader>ao` | `:ArmDump` | Build and show the disassembly (`objdump -d`) |
| `<leader>as` | `:ArmSyms` | Build and list every label with its address in hex |
| | `:ArmSetup` | macOS only: build the qemu Docker image |

Output opens in a split at the bottom; press `q` to close the `ArmDump` and `ArmSyms` views.
`Ctrl-C` stops a program that loops forever.

**Build flags:** `-march=armv7-a -marm -mbig-endian -nostdlib -static -g -Wl,--be8 -Wl,-Ttext=0`.
Code is linked at address **0**, like Keil uVision, so `<leader>as` shows the same label
addresses as Keil. GNU's `.word`/`.hword` don't align by themselves, unlike Keil's
`DCD`/`DCW`. Add `.balign 4` / `.balign 2` before them so the addresses match.

`<leader>as` output: `t`/`T` = in `.text`, `d`/`D` = in `.data`; uppercase = `.global`.
Linker-defined names (`_end`, `_stack`, …) are hidden; `_start` is kept.

## Debugger

`F5` or `<leader>ad` builds the file, starts it paused in qemu and opens a layout
modelled on uVision: **Registers** on the left, **Disassembly** on top, the source in the
middle, and **Command / Memory / Watch** at the bottom. Values that changed since the
last step are highlighted. Numbers are shown in hex.

| Key | Action |
|---|---|
| `F5` | Start / continue |
| `F9` | Toggle breakpoint |
| `F10` | Step over (one instruction) |
| `F11` | Step into (one instruction) |
| `Shift-F11` | Step out |
| `Ctrl-F10` / `<leader>dc` | Run to cursor |
| `<leader>dq` | Stop debugging |
| `<leader>du` | Toggle the debug UI |
| `<leader>de` | Evaluate expression under cursor / selection |
| `<leader>dw` | Add a watch |
| `<leader>dm` | Set the memory window address |
| `:ArmMem <addr> [bytes]` | Same, e.g. `:ArmMem &L4`, `:ArmMem $sp 64`, `:ArmMem 0x10` |

On macOS the F-keys may need `fn` (e.g. `fn-F10`).

Useful gdb commands in the Command window: `info address L4`, `p &L4`, `x/4xw &LA`, `p/x $r0`.

## Snippets

Type the trigger and accept it from the completion menu.

| File | Trigger | Inserts |
|---|---|---|
| `.s` | `start` | Program skeleton: hello-world `write` + `exit` syscalls |
| `.s` | `fn` | Function with `push {r4-r11, lr}` / `pop {r4-r11, pc}` |
| `.s` | `sys` | `mov r7, #n` + `svc #0` |
| `.tex` | `assigment` | Assignment template |

## General keys

From NvChad, plus `;` → `:` and `jk` → Escape in insert mode.

| Key | Action |
|---|---|
| `Ctrl-s` | Save |
| `Ctrl-c` | Copy whole file |
| `Esc` | Clear search highlight |
| `<leader>/` | Toggle comment (line or selection) |
| `<leader>fm` | Format file |
| `<leader>n` / `<leader>rn` | Toggle line numbers / relative numbers |
| `<leader>th` | Pick a theme |
| `<leader>ch` | Cheatsheet |

**Windows and buffers**

| Key | Action |
|---|---|
| `Ctrl-h/j/k/l` | Move between windows |
| `Tab` / `Shift-Tab` | Next / previous buffer |
| `<leader>b` | New buffer |
| `<leader>x` | Close buffer |
| `Ctrl-n` | Toggle file tree |
| `<leader>e` | Focus file tree |

**Find (Telescope)**

| Key | Action |
|---|---|
| `<leader>ff` | Files |
| `<leader>fa` | All files (hidden + ignored) |
| `<leader>fw` | Grep in project |
| `<leader>fz` | Search in current file |
| `<leader>fb` | Open buffers |
| `<leader>fo` | Recent files |
| `<leader>fh` | Help pages |
| `<leader>ma` | Marks |
| `<leader>cm` / `<leader>gt` | Git commits / git status |

**Terminal**

| Key | Action |
|---|---|
| `<leader>h` / `<leader>v` | New horizontal / vertical terminal |
| `Alt-h` / `Alt-v` / `Alt-i` | Toggle horizontal / vertical / floating terminal |
| `Ctrl-x` | Leave terminal mode |
| `<leader>pt` | Pick a hidden terminal |

## LSP, formatting, linting

Language servers: `lua_ls`, `clangd`, `asm_lsp` (installed by Mason).

| Key | Action |
|---|---|
| `gd` / `gD` | Go to definition / declaration |
| `K` | Hover docs |
| `<leader>D` | Go to type definition |
| `<leader>ra` | Rename symbol |
| `<leader>ds` | Diagnostics list |
| `<leader>wa` / `wr` / `wl` | Add / remove / list workspace folders |

Formatting on save: Lua (`stylua`), C/C++ (`clang-format`, 4-space indent).
Linting: Lua (`luacheck`).

## LaTeX

VimTeX with `latexmk`, PDF viewer `zathura`. Main keys:

| Key | Action |
|---|---|
| `<leader>ll` | Start / stop continuous compile |
| `<leader>lv` | Jump to position in PDF |
| `<leader>le` | Show errors |
| `<leader>lc` | Clean aux files |
| `<leader>lt` | Table of contents |
