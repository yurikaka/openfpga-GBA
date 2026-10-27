library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.pProc_bus_gba.all;

entity cart_save_memorymux_tb is end;
architecture test of cart_save_memorymux_tb is
    signal clk : std_logic := '0';
    signal reset, gb_on, physical : std_logic := '0';
    signal adr, dout, din : std_logic_vector(31 downto 0) := (others => '0');
    signal ena, rnw, done, cart_req, cart_wr, cart_done : std_logic := '0';
    signal acc, cart_acc : std_logic_vector(1 downto 0) := ACCESS_8BIT;
    signal lowbits : std_logic_vector(1 downto 0) := "00";
    signal cart_addr : std_logic_vector(27 downto 0);
    signal cart_wdata : std_logic_vector(31 downto 0);
    signal cart_rdata : std_logic_vector(31 downto 0) := x"5A5A5A5A";
    signal sdram_req, psram_req, gpio_read, gpio_write : std_logic;
    signal ss : proc_bus_gb_type := ((others => '0'), (others => 'Z'),
        (others => '0'), '1', '0', 'Z', "00", "0000", '1');
    signal regs : proc_bus_gb_type := ((others => 'Z'), (others => '0'),
        (others => 'Z'), 'Z', 'Z', '0', "ZZ", "ZZZZ", 'Z');
begin
    clk <= not clk after 5 ns;
    dut : entity work.gba_memorymux
    generic map (is_simu => '1', Softmap_GBA_Gamerom_ADDR => 0,
        Softmap_GBA_WRam_ADDR => 131072, Softmap_GBA_FLASH_ADDR => 0,
        Softmap_GBA_EEPROM_ADDR => 0)
    port map (
        clk100 => clk, gb_on => gb_on, reset => reset, savestate_bus => ss,
        sdram_read_ena => sdram_req, sdram_read_done => '0', sdram_read_addr => open,
        sdram_read_data => x"12345678", sdram_second_dword => x"90ABCDEF",
        bus_out_Din => open, bus_out_Dout => x"00000000", bus_out_Adr => open,
        bus_out_rnw => open, bus_out_ena => psram_req, bus_out_be => open, bus_out_done => '0',
        gb_bus_out => regs, mem_bus_Adr => adr, mem_bus_rnw => rnw,
        mem_bus_ena => ena, mem_bus_acc => acc, mem_bus_dout => dout,
        mem_bus_din => din, mem_bus_done => done, mem_bus_unread => open,
        bus_lowbits => lowbits, dma_soon => '0', settle => open,
        save_eeprom => open, save_sram => open, save_flash => open,
        new_cycles => to_unsigned(0, 8), new_cycles_valid => '0', PC_in_BIOS => '1',
        lastread => x"00000000", lastread_dma => x"00000000", last_access_dma => '0',
        dma_eepromcount => to_unsigned(0, 17), flash_1m => '1',
        MaxPakAddr => std_logic_vector(to_unsigned(8388608, 25)),
        SramFlashEnable => '1', memory_remap => '0', cartridge_save_mode => physical,
        cart_req => cart_req, cart_wr => cart_wr, cart_addr => cart_addr,
        cart_acc => cart_acc, cart_wdata => cart_wdata, cart_rdata => cart_rdata,
        cart_done => cart_done, bitmapdrawmode => '0',
        VRAM_Lo_addr => open, VRAM_Lo_datain => open, VRAM_Lo_dataout => x"00000000",
        VRAM_Lo_we => open, VRAM_Lo_be => open,
        VRAM_Hi_addr => open, VRAM_Hi_datain => open, VRAM_Hi_dataout => x"00000000",
        VRAM_Hi_we => open, VRAM_Hi_be => open, vram_blocked => '0', vram_cycle => open,
        OAMRAM_PROC_addr => open, OAMRAM_PROC_datain => open,
        OAMRAM_PROC_dataout => x"00000000", OAMRAM_PROC_we => open,
        PALETTE_BG_addr => open, PALETTE_BG_datain => open,
        PALETTE_BG_dataout => x"00000000", PALETTE_BG_we => open,
        PALETTE_OAM_addr => open, PALETTE_OAM_datain => open,
        PALETTE_OAM_dataout => x"00000000", PALETTE_OAM_we => open,
        specialmodule => '1', GPIO_readEna => gpio_read, GPIO_done => '0',
        GPIO_Din => "0000", GPIO_Dout => open, GPIO_writeEna => gpio_write,
        GPIO_addr => open, GPIO_readable => '1', tilt => '0',
        AnalogTiltX => to_signed(0, 8), AnalogTiltY => to_signed(0, 8), debug_mem => open
    );

    process
        procedure tick is begin wait until falling_edge(clk); end;
        procedure restart(constant backend : std_logic) is
        begin
            reset <= '1'; gb_on <= '0'; ss.rst <= '1'; ena <= '0'; cart_done <= '0';
            physical <= backend; lowbits <= "00";
            for i in 1 to 4 loop tick; end loop;
            reset <= '0'; gb_on <= '1'; ss.rst <= '0';
            -- Prime the upstream address pipeline with a harmless BIOS read.
            adr <= x"00000000"; rnw <= '1'; acc <= ACCESS_32BIT; ena <= '1';
            tick; ena <= '0';
            -- Upstream clears all 1024 ROM-cache tags after GBA power-on.
            for i in 1 to 1100 loop tick; end loop;
        end;
        procedure request(constant address, data : std_logic_vector(31 downto 0);
                          constant size : std_logic_vector(1 downto 0);
                          constant read_op : std_logic) is
        begin
            adr <= address; dout <= data; acc <= size; rnw <= read_op; ena <= '1';
            tick; ena <= '0'; tick;
        end;
        procedure physical_access(constant address, data, response, expected : std_logic_vector(31 downto 0);
                                  constant size : std_logic_vector(1 downto 0);
                                  constant read_op : std_logic;
                                  constant original_lowbits : std_logic_vector(1 downto 0) := "00";
                                  constant expected_address : std_logic_vector(31 downto 0) := x"00000000") is
            variable target : std_logic_vector(31 downto 0);
        begin
            target := address;
            if expected_address /= x"00000000" then target := expected_address; end if;
            lowbits <= original_lowbits;
            cart_rdata <= response;
            request(address, data, size, read_op);
            assert cart_req = '1' and cart_addr = target(27 downto 0) and
                   cart_acc = size and cart_wr = not read_op and cart_wdata = data
                report "physical request address/data/direction mismatch" severity failure;
            for i in 1 to 4 loop
                assert done = '0' and psram_req = '0' and sdram_req = '0' and
                       gpio_read = '0' and gpio_write = '0'
                    report "physical access acknowledged early or leaked to emulation" severity failure;
                tick;
            end loop;
            cart_done <= '1'; tick; cart_done <= '0';
            assert done = '1' report "physical completion missing" severity failure;
            if read_op = '1' then
                assert din = expected report "physical read lane mismatch" severity failure;
            end if;
            tick;
        end;
    begin
        tick; restart('1');
        physical_access(x"0E000123", x"00000000", x"5A5A5A5A", x"0000005A", ACCESS_8BIT, '1');
        physical_access(x"0E005555", x"000000AA", x"00000000", x"00000000", ACCESS_8BIT, '0');
        physical_access(x"0E002AAA", x"00000055", x"00000000", x"00000000", ACCESS_8BIT, '0');
        physical_access(x"0E000000", x"00000000", x"A5A5A5A5", x"0000A5A5", ACCESS_16BIT, '1');
        physical_access(x"0E000000", x"00000000", x"12121212", x"12121212", ACCESS_32BIT, '1');
        -- CPU LDM/STM presents an aligned address plus the original low bits.
        physical_access(x"0E000120", x"00000000", x"12121212", x"12121212", ACCESS_32BIT, '1', "00", x"0E000120");
        physical_access(x"0E000120", x"00000000", x"12121212", x"12121212", ACCESS_32BIT, '1', "01", x"0E000121");
        physical_access(x"0E000120", x"00000000", x"12121212", x"12121212", ACCESS_32BIT, '1', "10", x"0E000122");
        physical_access(x"0E000120", x"00000000", x"12121212", x"12121212", ACCESS_32BIT, '1', "11", x"0E000123");
        physical_access(x"0F000120", x"44332211", x"00000000", x"00000000", ACCESS_32BIT, '0', "00", x"0F000120");
        physical_access(x"0F000120", x"44332211", x"00000000", x"00000000", ACCESS_32BIT, '0', "01", x"0F000121");
        physical_access(x"0F000120", x"44332211", x"00000000", x"00000000", ACCESS_32BIT, '0', "10", x"0F000122");
        physical_access(x"0F000120", x"44332211", x"00000000", x"00000000", ACCESS_32BIT, '0', "11", x"0F000123");
        physical_access(x"0E000121", x"00000000", x"12121212", x"12121212", ACCESS_32BIT, '1', "10", x"0E000123");
        physical_access(x"080000C5", x"00000000", x"00001234", x"00000012", ACCESS_8BIT, '1');
        physical_access(x"080000C8", x"00000001", x"00000000", x"00000000", ACCESS_16BIT, '0', "11");

        request(x"08000100", x"00000000", ACCESS_32BIT, '1');
        for i in 1 to 30 loop
            assert cart_req = '0' report "ROM read escaped SDRAM" severity failure;
            exit when sdram_req = '1'; tick;
        end loop;
        assert sdram_req = '1' report "ROM did not request SDRAM" severity failure;

        restart('0');
        request(x"0E000123", x"00000000", ACCESS_8BIT, '1');
        for i in 1 to 30 loop
            assert cart_req = '0' report "SD fallback touched cartridge" severity failure;
            exit when psram_req = '1'; tick;
        end loop;
        assert psram_req = '1' report "SD fallback did not use PSRAM" severity failure;
        restart('0');
        request(x"080000C4", x"00000000", ACCESS_16BIT, '1');
        assert gpio_read = '1' and cart_req = '0' report "SD GPIO fallback failed" severity failure;
        restart('0');
        request(x"080000C8", x"00000001", ACCESS_16BIT, '0');
        assert gpio_write = '1' and cart_req = '0' report "SD GPIO write fallback failed" severity failure;
        report "cart_save_memorymux_tb passed" severity note;
        stop;
        wait;
    end process;
    process begin wait for 200 us; assert false report "timeout" severity failure; end process;
end;
