# SD ROM with physical Flash saves

This experimental mode runs the selected SD ROM from SDRAM while sending its
Flash save accesses directly to the inserted cartridge. This branch is based
on upstream v1.0.1 and always runs the selected ROM from SD/SDRAM.

At boot, the GBA remains in reset until a read-only cartridge probe completes.
Physical saves are selected only when:

* Both ROM headers have the same valid four-character game code (0xAC–0xAF).
* Both ROMs contain a recognized Flash library tag: `FLASH_V` / `FLASH512_V`
  for 64 KiB, or `FLASH1M_V` for 128 KiB.
* The Flash capacities match, with no SRAM, EEPROM or conflicting Flash tags.

The SD ROM is checked as it loads. The physical ROM is scanned across its
32 MiB address window before Flash is accepted; this adds a boot delay. An
SRAM/EEPROM tag, unknown save type, mismatched game code, incompatible capacity,
missing cartridge, unsupported adapter or probe timeout selects normal SD saves.
The probe never sends Flash identification commands or writes to save memory.
Library tags describe the cartridge software; they cannot prove what save
hardware a reproduction cartridge actually contains. Matching game codes also
do not establish save compatibility for arbitrary ROM hacks.

When physical saves are selected:

* Save reads and writes go directly to the cartridge. SD save data is never
  copied onto it, and physical save changes are not copied back to an SD file.
* Both the save and RTC data-table sizes are zero, disabling SD writeback of
  the `.sav` and separate RTC sidecar used by upstream v1.0.1.
* Save states are disabled.
* RTC/GPIO accesses use the cartridge hardware when enabled for the game.

The upstream rumble driver is paused during detection and while physical saves
own the slot. SD fallback restores the upstream rumble behavior. The probe starts
after the new shared write-ingress fence has drained, so every ROM word has been
included in save-type detection. Pocket firmware 1.2 or newer is required for
the cartridge-power notification; the core requests power without adding a
Play Cartridge menu entry.

The backend is fixed until the FPGA is reloaded. Do not remove or exchange the
cartridge during play. An in-game save changes the real cartridge save.

## Validation

Run `bash scripts/test_cart_save.sh` with Icarus Verilog (`iverilog` and `vvp`).
The `IVERILOG` and `VVP` variables can point to downloaded tool binaries.
Tests cover signature alignment, backend selection and fallback, immutable boot
decisions, and the existing cartridge pin-level bus behavior. These simulations
do not replace a full Quartus build, timing analysis or testing on a Pocket.

Run `bash scripts/test_cart_save_vhdl.sh` with GHDL (`GHDL` can specify its
absolute binary path) to test the actual upstream memory mux. It checks Flash
command writes and read lanes, direct GPIO/RTC accesses, completion handshakes,
SDRAM ROM reads even while in BIOS, and PSRAM/GPIO fallback to upstream behavior.
