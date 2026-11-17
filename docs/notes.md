# Game Boy on FPGA: Project Plan

**Board:** Nexys A7-100T | **Tools:** Vivado + SystemVerilog | **Time:** 3 weeks, 2 people, limited hours

This plan is split between two people, called **A** (CPU side) and **B** (memory and video side). Swap the roles however you like.

---

## 1. The big picture

A Game Boy is made of a few cooperating pieces:

| Piece | What it does | Our files |
|---|---|---|
| **CPU** | Reads instructions from the game and executes them | `rtl/cpu/` |
| **Memory** | Stores the game code, working data, and graphics data | `rtl/bus/` |
| **PPU** (Picture Processing Unit) | Reads graphics data and draws the 160x144 screen | `rtl/ppu/` |
| **I/O** | Buttons, timer, interrupts | `rtl/io/` |
| **Video output** | Converts the Game Boy picture into a VGA signal | `rtl/video/` |
| **Bus** | The shared wires that connect everything above | `rtl/bus/bus_decoder.sv`, `rtl/gb_pkg.sv` |

---

## 2. What is the bus?

A **bus** is a group of shared wires that the CPU uses to talk to everything else. Think of it as a hallway with numbered doors. The CPU says "I want to talk to door number X" (the **address**), and either hands over some data (a **write**) or asks for some (a **read**). The device behind that door answers.

The Game Boy's bus has three parts:

| Signal | Width | Meaning |
|---|---|---|
| `addr` | 16 bits | Which location the CPU wants. 16 bits gives 65,536 locations (0x0000 to 0xFFFF). |
| `wdata` | 8 bits | Data the CPU is writing |
| `rdata` | 8 bits | Data coming back to the CPU when it reads |
| `rd` / `wr` | 1 bit each | Says whether this cycle is a read or a write |

The **bus decoder** (`bus_decoder.sv`) is the piece that looks at `addr` and decides which device gets the request. The Game Boy's **memory map** defines which addresses belong to which device:

| Address range | Device |
|---|---|
| `0x0000` - `0x7FFF` | Game ROM (the cartridge) |
| `0x8000` - `0x9FFF` | VRAM (video RAM: tile images and the tile map) |
| `0xA000` - `0xBFFF` | Cartridge RAM (not needed for Tetris) |
| `0xC000` - `0xDFFF` | WRAM (work RAM, the CPU's scratch space) |
| `0xE000` - `0xFDFF` | Echo of WRAM (rarely used; can ignore) |
| `0xFE00` - `0xFE9F` | OAM (the sprite list) |
| `0xFF00` - `0xFF7F` | I/O registers (joypad, timer, serial, PPU settings) |
| `0xFF80` - `0xFFFE` | HRAM (small fast RAM) |
| `0xFFFF` | Interrupt enable register |

For example, if the CPU reads address `0x9800`, the decoder routes that request to VRAM. If it writes to `0xFF01`, the decoder routes it to the serial register.

**Why this matters for teamwork:** A builds the CPU, which only knows how to put addresses and data on the bus. B builds the devices, which only know how to respond to the bus. If you agree on the bus signals on day 1, you can build and test your halves separately, and they will plug together later.

A starting point for the shared definition (in `rtl/gb_pkg.sv` or a shared interface):

```systemverilog
// Bus signals shared by the CPU and every device
logic [15:0] addr;    // which location
logic [7:0]  wdata;   // data the CPU writes
logic [7:0]  rdata;   // data the device returns
logic        rd;      // CPU is reading
logic        wr;      // CPU is writing
```

---

## 3. Phase 0: Setup (day 1, together)

- [ ] Create the Git repository and make sure both of you can push and pull
- [ ] Run the folder setup command and commit the empty layout
- [ ] Add a `.gitignore` that excludes `vivado/`, `*.jou`, `*.log`, `*.str`, `*.backup.*`, `.Xil/`
- [ ] Write `scripts/create_project.tcl` so Vivado projects can be rebuilt from source (a Tcl script is a list of Vivado commands)
- [ ] Copy Digilent's master XDC for the Nexys A7 into `constraints/` and keep only the pins you use (clock, VGA, buttons). The XDC file maps the FPGA's pins to board features.
- [ ] Skim the **Pan Docs**, the community Game Boy reference (gbdev.io/pandocs)
- [ ] **Agree on the bus signals** and write them in `rtl/gb_pkg.sv`
- [ ] Download the test ROMs: **Blargg's cpu_instrs** (put them in `roms/tests/`)

---

## 4. Phase 1: Foundations (week 1)

### Person A: CPU core

The CPU is a small machine that repeatedly **fetches** an instruction from memory, **decodes** it (figures out what it means), and **executes** it.

- [ ] `regfile.sv`: the CPU's registers. These are small storage slots inside the CPU: A, F (flags), B, C, D, E, H, L, plus the stack pointer (SP) and program counter (PC). The PC holds the address of the next instruction.
- [ ] `alu.sv` and `tb_alu.sv`: the **ALU** (arithmetic logic unit) does the math (add, subtract, AND, OR, shifts). Test it with many input combinations, including how it sets the flags (Zero, Negative, Half-carry, Carry).
- [ ] `decoder.sv`: turns an instruction byte into control signals
- [ ] First version of `cpu.sv` handling a **subset** of instructions (loads, adds, jumps, compares, calls), enough to run a small program
- [ ] **Skip the boot ROM** (it is copyrighted). Start the PC at `0x0100` with the registers set to the values the boot ROM would have left behind. These are in Pan Docs under "Power Up Sequence".

### Person B: memory and video

- [ ] `wram.sv`, `hram.sv`, `vram.sv`: simple RAM modules (they map onto the FPGA's block RAM, its built-in memory)
- [ ] `cart_rom.sv`: holds the game, loaded from a file when the FPGA is programmed
- [ ] `bus_decoder.sv`: routes each address to the right device, following the memory map above
- [ ] `scripts/rom2mem.py`: converts a `.gb` file into a memory initialization file that Vivado can preload into block RAM
- [ ] `vga_timing.sv`: generates the VGA sync signals for 640x480
- [ ] `framebuffer.sv`: memory holding the current picture. Show a **test pattern** (color bars or a gradient) on the monitor.

### Milestone 1 (end of week 1)

> The CPU runs a tiny hand-written program in simulation, and a test pattern shows on the monitor.

### Decision checkpoint

If the CPU cannot run even a simple program by the end of week 1, switch to a smaller project (Bitcoin miner or CHIP-8). Both can still be finished in two weeks.

---

## 5. Phase 2: Core functionality (week 2)

### Person A: finish the CPU

- [ ] Implement all remaining instructions, including the **CB-prefixed** group (an extra set of instructions for bit tests and shifts, reached through a prefix byte `0xCB`)
- [ ] `interrupt_ctrl.sv`: **interrupts** are signals that make the CPU pause what it is doing and jump to special handler code (for example, when a frame finishes drawing)
- [ ] `timer.sv`: a counter that the game can read and that can trigger an interrupt
- [ ] Capture **serial output**. The Blargg test ROMs print their results by writing to the serial registers at `0xFF01` and `0xFF02`. Print these bytes in simulation (`$display`) or send them out over UART.
- [ ] Run each Blargg cpu_instrs sub-test (there are 11) and fix failures one at a time

### Person B: background graphics

- [ ] `ppu.sv` and `bg_fetch.sv`: the Game Boy screen is built from **tiles**, small 8x8-pixel pictures stored in VRAM. A **tile map** (a grid in VRAM) says which tile goes where. The PPU reads the tile map, fetches each tile's pixels, and applies a palette (the mapping from pixel values to the 4 gray shades).
- [ ] `scaler.sv`: scale 160x144 up by 3x to 480x432 and center it on the 640x480 VGA screen
- [ ] Test by filling VRAM by hand (or with a short test ROM) and confirming the tiles draw correctly

### Milestone 2 (end of week 2)

> The CPU passes the Blargg tests in simulation, and a background draws correctly on the monitor.

---

## 6. Phase 3: Integration and finish (week 3)

| Task | Owner |
|---|---|
| Connect CPU, bus, memories, and PPU in `rtl/gb_top.sv`; run a ROM end to end on the board | A + B |
| `joypad.sv`: read the board's buttons as the Game Boy's buttons | A |
| `oam_dma.sv` and `sprite_engine.sv`: **sprites** are movable objects (like the falling Tetris piece); **OAM DMA** is a fast copy of the sprite list into OAM (stretch goal) | B |
| Final testbenches, waveform screenshots, Vivado utilization report | A + B |
| Report and demo | A + B |

**Rule:** the last 3 to 4 days are for the write-up and demo only. Do not start new features then.

---

## 7. Fallback ladder (what counts as done)

| Level | Result | Likelihood in 3 weeks |
|---|---|---|
| 1 | CPU passes Blargg tests | Realistic |
| 2 | Level 1 + a background draws on VGA from a ROM | **Target** |
| 3 | Level 2 + joypad and sprites | Possible if all goes well |
| 4 | Tetris playable | Unlikely at this pace |

Tetris needs sprites, interrupts, the timer, DMA, and the joypad all working together, so treat it as a bonus.

---

## 8. Good habits

- **Test each module on its own** before connecting it (one testbench per module in `sim/`). A **testbench** is a SystemVerilog file that feeds inputs to a module and checks its outputs.
- **Commit often**, and avoid both people editing the same file at once.
- **Keep notes** as you go (what broke, what fixed it). These become most of your report.
- **Take waveform screenshots** of passing tests for the report.
- **Check in briefly** at the start of each phase to make sure the bus interface has not drifted.

---

## 9. Handy references

- **Pan Docs** (gbdev.io/pandocs): CPU instructions, memory map, PPU behavior, power-up register values
- **Blargg's test ROMs**: `cpu_instrs` for CPU verification
- **Digilent Nexys A7 reference manual** and master XDC: pin names and board features