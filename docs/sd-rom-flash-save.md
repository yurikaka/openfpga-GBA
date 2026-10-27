# SD ROM with physical Flash saves — unchecked test mode

This experimental branch is based on upstream v1.0.1. It runs the selected SD
ROM from SDRAM while sending Flash save accesses directly to the inserted
cartridge. During testing, the operator guarantees that both the SD ROM and
physical cartridge use 128 KiB Flash and compatible save data.

Game-code matching and Flash type/capacity detection are temporarily removed.
The core does not read the physical ROM header or scan its ROM for library tags.
It cannot detect a missing cartridge, a different game, SRAM/EEPROM, or a
different Flash capacity. These conditions no longer trigger SD fallback.

The GBA stays in reset until the ROM loader is fully drained and the OS sends
Reset Exit. The OS cartridge-power notification announces future power; it is
not treated as evidence that the slot is already powered during loading.
Physical saves are selected when the OS enables cartridge power with the native
GBA interface. An unpowered slot or unsupported adapter selects SD saves.

When physical saves are selected:

* Flash reads and writes go directly to the cartridge. SD save data is never
  copied onto it, and physical save changes are not copied back to an SD file.
* Both the save and RTC data-table sizes are zero to disable SD writeback of
  the `.sav` and separate RTC sidecar used by upstream v1.0.1.
* Save states are disabled.
* RTC/GPIO accesses use the cartridge hardware when enabled for the game.

The upstream rumble driver is paused until backend selection and while physical
saves own the slot. SD fallback restores the upstream rumble behavior. Pocket
firmware 1.2 or newer is required for the cartridge-power notification; the core
requests power without adding a Play Cartridge menu entry.

The backend is fixed until the FPGA is reloaded. Do not remove or exchange the
cartridge during play. An in-game save changes the real cartridge save.
The upstream SD save detector remains for normal SD fallback and game quirks;
its result does not gate physical-save selection.

## Validation

Run `bash scripts/test_cart_save.sh` with Icarus Verilog (`iverilog` and `vvp`).
The `IVERILOG` and `VVP` variables can point to downloaded tool binaries.
Tests cover OS reset/loader ordering, power/adapter fallback, immutable backend
selection, and cartridge pin-level bus behavior. SRAM/Flash tests cover every
address low-bit pattern and CPU access width, with exactly one byte transfer per
access and the correct write-data byte. ROM/GPIO word transfers and EEPROM
serial behavior are checked separately.

Run `bash scripts/test_cart_save_vhdl.sh` with GHDL (`GHDL` can specify its
absolute binary path) to test the actual upstream memory mux. It checks Flash
command writes and read lanes, direct GPIO/RTC accesses, completion handshakes,
SDRAM ROM reads even while in BIOS, and PSRAM/GPIO fallback to upstream behavior.
It also checks restoration of the CPU block-transfer address low bits in the
physical SRAM/Flash regions, including the mirrored region.
These simulations do not replace a full Quartus build, external cartridge I/O
timing verification, or testing on a Pocket.
