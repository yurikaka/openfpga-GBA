`timescale 1ns/1ps
`default_nettype none

module gba_cart_bus_tb;

reg clk = 1'b0;
always #5 clk = ~clk;

reg reset = 1'b1;
reg cart_mode = 1'b0;
reg req = 1'b0;
reg wr = 1'b0;
reg [27:0] addr = 28'd0;
reg [1:0] acc = 2'b01;
reg [31:0] wdata = 32'd0;
wire [31:0] rdata;
wire done;
wire busy;

tri [7:0] bank2;
tri [7:0] bank3;
wire bank2_dir;
wire bank3_dir;
tri [7:0] bank1;
wire bank1_dir;
tri [7:4] bank0;
wire bank0_dir;
tri pin30;
wire pin30_dir;
wire pin30_pwroff_reset;
tri pin31;
wire pin31_dir;
wire [7:0] out1, out2, out3;
assign bank1 = bank1_dir ? out1 : 8'hzz;
assign bank2 = bank2_dir ? out2 : 8'hzz;
assign bank3 = bank3_dir ? out3 : 8'hzz;

reg [15:0] cart_drive_data = 16'hCAFE;
wire cart_read_active = cart_mode && !bank3_dir && !bank2_dir && (bank0[5] == 1'b0);
assign bank3 = cart_read_active ? cart_drive_data[7:0] : 8'hzz;
assign bank2 = cart_read_active ? cart_drive_data[15:8] : 8'hzz;

reg use_rom_sequence = 1'b0;
integer rom_rd_count = 0;
reg cs_rose_between_seq = 1'b0;
reg monitor_eeprom_hold = 1'b0;
reg eeprom_cs_rose = 1'b0;

always @(negedge bank0[5]) begin
    #1;
    if (use_rom_sequence && cart_mode && pin30 === 1'b1 && bank0[4] === 1'b0) begin
        case (rom_rd_count)
            0: cart_drive_data <= 16'h1122;
            1: cart_drive_data <= 16'h3344;
            default: cart_drive_data <= 16'h5566;
        endcase
        rom_rd_count <= rom_rd_count + 1;
    end
end

always @(posedge bank0[4]) begin
    #1;
    if (use_rom_sequence && busy && rom_rd_count == 1)
        cs_rose_between_seq <= 1'b1;
    if (monitor_eeprom_hold)
        eeprom_cs_rose <= 1'b1;
end

reg [7:0] save_drive_data = 8'hA5;
wire save_read_active = cart_mode && !bank1_dir && (pin30 == 1'b0) && (bank0[5] == 1'b0);
assign bank1 = save_read_active ? save_drive_data : 8'hzz;

integer save_write_count = 0, save_read_count = 0;
reg check_save_write = 0;
reg [15:0] expected_save_addr;
reg [7:0] expected_save_data;
reg check_gpio_word = 0;
integer gpio_write_count = 0;
always @(negedge bank0[4]) begin
    if (check_gpio_word && {bank1, bank2, bank3} !== (24'h62 + 24'(gpio_write_count)))
        $fatal(1, "GPIO word store address mismatch");
end
always @(negedge bank0[6]) begin
    if (cart_mode && pin30 === 1'b0) begin
        save_write_count = save_write_count + 1;
        if (check_save_write &&
            ({bank2, bank3} !== expected_save_addr || bank1 !== expected_save_data ||
             !bank1_dir || !bank2_dir || !bank3_dir || bank0[4] !== 1'b1))
            $fatal(1, "save write pins: addr=%h data=%h expected=%h/%h",
                   {bank2, bank3}, bank1, expected_save_addr, expected_save_data);
    end
    if (check_gpio_word) begin
        if (pin30 !== 1'b1 || bank0[4] !== 1'b0 ||
            {bank2, bank3} !== (gpio_write_count == 0 ? 16'h1122 : 16'h3344))
            $fatal(1, "GPIO word store halfword mismatch");
        gpio_write_count = gpio_write_count + 1;
    end
end
always @(negedge bank0[5])
    if (cart_mode && pin30 === 1'b0) save_read_count = save_read_count + 1;

reg monitor_eeprom_write = 1'b0;
reg eeprom_write_seen = 1'b0;
reg eeprom_write_setup_seen = 1'b0;
reg [15:0] eeprom_expected_write = 16'h0000;
always @(posedge clk) begin
    #1;
    if (monitor_eeprom_write && bank0[6] === 1'b1 && bank0[4] === 1'b0 &&
        bank3_dir === 1'b1 && bank2_dir === 1'b1 && {bank2, bank3} === eeprom_expected_write) begin
        eeprom_write_setup_seen <= 1'b1;
    end
    if (monitor_eeprom_write && bank0[6] === 1'b0) begin
        eeprom_write_seen <= 1'b1;
        if (!eeprom_write_setup_seen)
            $fatal(1, "EEPROM write data was not setup before WR# asserted");
        if (bank0[4] !== 1'b0 || pin30 !== 1'b1)
            $fatal(1, "EEPROM write did not select CS1 only");
        if (bank3_dir !== 1'b1 || bank2_dir !== 1'b1)
            $fatal(1, "EEPROM write did not drive AD data");
        if ({bank2, bank3} !== eeprom_expected_write)
            $fatal(1, "EEPROM write data was %h", {bank2, bank3});
    end
end

// After a read, RD# returns high before CS# rises; AD must remain released
// during that interval and between sequential beats. Check address setup
// only before the first read pulse in a chip-select window.
reg rom_read_seen = 1'b0;
always @(posedge bank0[4]) rom_read_seen = 1'b0;
always @(negedge bank0[5]) rom_read_seen = 1'b1;

always @(posedge clk) begin
    #1;
    if (cart_mode && !wr && busy && !rom_read_seen && pin30 === 1'b1 && bank0[4] === 1'b0 && bank0[5] === 1'b1) begin
        if (bank3_dir !== 1'b1 || bank2_dir !== 1'b1)
            $fatal(1, "ROM address bus released before RD# asserted");
    end
end

gba_cart_bus #(
    .ADDR_HOLD_CYCLES  (1),
    .ADDR_LATCH_CYCLES (1),
    .READ_TURNAROUND_CYCLES(1),
    .READ_SETUP_CYCLES (2),
    .WRITE_SETUP_CYCLES(1),
    .WRITE_HOLD_CYCLES (1)
) dut (
    .clk(clk),
    .reset(reset),
    .cart_mode(cart_mode),
    .req(req),
    .wr(wr),
    .addr(addr),
    .acc(acc),
    .wdata(wdata),
    .rdata(rdata),
    .done(done),
    .busy(busy),
    .cart_tran_bank2(bank2),
    .cart_tran_bank2_out(out2),
    .cart_tran_bank2_dir(bank2_dir),
    .cart_tran_bank3(bank3),
    .cart_tran_bank3_out(out3),
    .cart_tran_bank3_dir(bank3_dir),
    .cart_tran_bank1(bank1),
    .cart_tran_bank1_out(out1),
    .cart_tran_bank1_dir(bank1_dir),
    .cart_tran_bank0(bank0),
    .cart_tran_bank0_dir(bank0_dir),
    .cart_tran_pin30(pin30),
    .cart_tran_pin30_dir(pin30_dir),
    .cart_pin30_pwroff_reset(pin30_pwroff_reset),
    .cart_tran_pin31(pin31),
    .cart_tran_pin31_dir(pin31_dir)
);

task automatic pulse_req(input bit is_write, input [27:0] a, input [1:0] size, input [31:0] d);
begin
    @(posedge clk);
    wr <= is_write;
    addr <= a;
    acc <= size;
    wdata <= d;
    req <= 1'b1;
    @(posedge clk);
    req <= 1'b0;
    wait (done == 1'b1);
    @(posedge clk);
end
endtask

task automatic check_save_access(input [27:0] a, input [1:0] size, input [7:0] expected);
    integer count_before;
    begin
        expected_save_addr = a[15:0];
        expected_save_data = expected;
        check_save_write = 1;
        count_before = save_write_count;
        pulse_req(1'b1, a, size, 32'h44332211);
        check_save_write = 0;
        if (save_write_count != count_before + 1)
            $fatal(1, "save store size=%b address=%h produced %0d writes",
                   size, a, save_write_count - count_before);
        count_before = save_read_count;
        pulse_req(1'b0, a, size, 32'd0);
        if (save_read_count != count_before + 1 || rdata !== 32'hA5A5A5A5)
            $fatal(1, "save read width/replication mismatch");
    end
endtask

integer lane, mirror;
reg [27:0] save_test_addr;
initial begin
    repeat (2) @(posedge clk);
    if (bank3_dir !== 1'b0 || bank2_dir !== 1'b0 || pin30_dir !== 1'b0)
        $fatal(1, "idle outside cart_mode drives bidirectional pins");

    reset <= 1'b0;
    cart_mode <= 1'b1;
    repeat (2) @(posedge clk);
    if (pin30_pwroff_reset !== 1'b1)
        $fatal(1, "cart power/reset release not asserted in cart_mode");

    cart_drive_data <= 16'hBEEF;
    pulse_req(1'b0, 28'h0000120, 2'b01, 32'd0);
    if (rdata[15:0] !== 16'hBEEF)
        $fatal(1, "ROM read returned %h", rdata);
    if (bank3_dir !== 1'b0 || bank2_dir !== 1'b0)
        $fatal(1, "AD bus still driven after read completion");

    use_rom_sequence <= 1'b1;
    rom_rd_count <= 0;
    cs_rose_between_seq <= 1'b0;
    pulse_req(1'b0, 28'h0000120, 2'b10, 32'd0);
    use_rom_sequence <= 1'b0;
    if (rdata !== 32'h33441122)
        $fatal(1, "32-bit ROM read returned %h", rdata);
    if (rom_rd_count !== 2)
        $fatal(1, "32-bit ROM read used %0d RD pulses", rom_rd_count);
    if (cs_rose_between_seq)
        $fatal(1, "CS# rose between sequential ROM word beats");

    save_drive_data <= 8'hA5;
    pulse_req(1'b0, 28'hE000123, 2'b00, 32'd0);
    if (rdata !== 32'hA5A5A5A5)
        $fatal(1, "save read returned %h", rdata);
    if (bank3_dir !== 1'b0 || bank2_dir !== 1'b0 || bank1_dir !== 1'b0)
        $fatal(1, "save read bus still driven after completion");

    pulse_req(1'b1, 28'hE000123, 2'b00, 32'h0000005A);
    if (pin30 !== 1'b1 || pin30_dir !== 1'b1)
        $fatal(1, "CS2 did not return high after save write");
    if (bank0[6] !== 1'b1)
        $fatal(1, "WR# did not return high after write");

    // SRAM/Flash and its mirror: all widths and all address low-bit patterns.
    for (mirror = 0; mirror < 2; mirror = mirror + 1) begin
        for (lane = 0; lane < 4; lane = lane + 1) begin
            save_test_addr = (mirror ? 28'hF000120 : 28'hE000120) + 28'(lane);
            check_save_access(save_test_addr, 2'b00, 8'h11);
            check_save_access(save_test_addr, 2'b01, (lane % 2) ? 8'h22 : 8'h11);
            case (lane)
                0: check_save_access(save_test_addr, 2'b10, 8'h11);
                1: check_save_access(save_test_addr, 2'b10, 8'h22);
                2: check_save_access(save_test_addr, 2'b10, 8'h33);
                3: check_save_access(save_test_addr, 2'b10, 8'h44);
            endcase
        end
    end

    // A GPIO word store still needs two addressed halfword writes.
    check_gpio_word = 1;
    pulse_req(1'b1, 28'h80000C4, 2'b10, 32'h33441122);
    check_gpio_word = 0;
    if (gpio_write_count != 2) $fatal(1, "GPIO word store lost its second beat");

    eeprom_write_seen <= 1'b0;
    eeprom_write_setup_seen <= 1'b0;
    eeprom_expected_write <= 16'h0001;
    monitor_eeprom_write <= 1'b1;
    pulse_req(1'b1, 28'hD000000, 2'b01, 32'h00000001);
    monitor_eeprom_write <= 1'b0;
    if (!eeprom_write_seen)
        $fatal(1, "EEPROM write never asserted WR#");
    if (bank0[4] !== 1'b0)
        $fatal(1, "EEPROM CS1 was not held after first serial bit");

    eeprom_cs_rose <= 1'b0;
    monitor_eeprom_hold <= 1'b1;
    eeprom_write_seen <= 1'b0;
    eeprom_write_setup_seen <= 1'b0;
    eeprom_expected_write <= 16'h0000;
    monitor_eeprom_write <= 1'b1;
    pulse_req(1'b1, 28'hD000000, 2'b01, 32'h00000000);
    monitor_eeprom_write <= 1'b0;
    monitor_eeprom_hold <= 1'b0;
    if (!eeprom_write_seen)
        $fatal(1, "second EEPROM write never asserted WR#");
    if (eeprom_cs_rose)
        $fatal(1, "EEPROM CS1 rose between serial bit writes");
    if (bank0[4] !== 1'b0)
        $fatal(1, "EEPROM CS1 was not held after second serial bit");

    eeprom_cs_rose <= 1'b0;
    monitor_eeprom_hold <= 1'b1;
    pulse_req(1'b0, 28'hD000000, 2'b01, 32'd0);
    monitor_eeprom_hold <= 1'b0;
    if (!eeprom_cs_rose)
        $fatal(1, "EEPROM CS1 did not release on write-to-read direction change");
    if (bank0[4] !== 1'b0)
        $fatal(1, "EEPROM CS1 was not held after first read bit");

    cart_drive_data <= 16'h1234;
    pulse_req(1'b0, 28'h0000120, 2'b01, 32'd0);
    if (bank0[4] !== 1'b1)
        $fatal(1, "EEPROM CS1 did not release on non-EEPROM access");

    cart_mode <= 1'b0;
    repeat (2) @(posedge clk);
    if (bank3_dir !== 1'b0 || bank2_dir !== 1'b0 || pin30_dir !== 1'b0)
        $fatal(1, "cart_mode deassert did not tri-state bidirectional pins");

    $display("gba_cart_bus_tb passed");
    $finish;
end

endmodule
