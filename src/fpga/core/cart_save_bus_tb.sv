`timescale 1ns/1ps
`default_nettype none

// Exercise the actual pin-level bus, not an immediate request/response stub.
module cart_save_bus_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, boot_ready = 0;
    wire req, probing, done, valid, use_cart, timed_out, bus_done;
    wire [27:0] addr;
    wire [31:0] physical_id, rdata;
    tri [7:0] bank1, bank2, bank3;
    tri [7:4] bank0;
    tri pin30, pin31;
    wire dir1, dir2, dir3;
    wire [7:0] out1, out2, out3;
    assign bank1 = dir1 ? out1 : 8'hzz;
    assign bank2 = dir2 ? out2 : 8'hzz;
    assign bank3 = dir3 ? out3 : 8'hzz;
    reg [7:0] image [0:1023];
    reg [23:0] word_addr;
    integer reads = 0;
    wire reading = !bank0[4] && !bank0[5] && !dir2 && !dir3;
    wire [9:0] byte_addr = {word_addr[8:0], 1'b0};
    assign bank3 = reading ? image[byte_addr] : 8'hzz;
    assign bank2 = reading ? image[byte_addr + 10'd1] : 8'hzz;

    always @(negedge bank0[4]) begin
        if (!reset) begin
            if (!dir1 || !dir2 || !dir3 || pin30 !== 1'b1)
                $fatal(1, "ROM address was not driven at CS1 assertion");
            word_addr = {bank1, bank2, bank3};
            if ({bank1, bank2, bank3} >= 512)
                $fatal(1, "probe outside ROM test window");
        end
    end
    always @(negedge bank0[5]) if (!reset) reads = reads + 1;
    always @(negedge bank0[6]) if (!reset) $fatal(1, "probe asserted WR#");
    always @(negedge pin30) if (!reset) $fatal(1, "probe selected save memory");

    cart_save_selector #(.TIMEOUT_CYCLES(200), .MAX_SCAN_BYTES(1024)) selector (
        .clk(clk), .reset(reset), .boot_ready(boot_ready), .cart_power(1'b1),
        .native_adapter(1'b1), .play_cartridge(1'b0), .rom_id("BPEJ"),
        .rom_id_valid(1'b1), .rom_flash_64(1'b0), .rom_flash_128(1'b1),
        .rom_other_save(1'b0), .probe_req(req), .probe_addr(addr),
        .probe_response(probing && bus_done), .probe_rdata(rdata),
        .probing(probing), .decision_done(done), .physical_id(physical_id),
        .physical_id_valid(valid), .use_cart_save(use_cart), .probe_timeout(timed_out)
    );
    gba_cart_bus bus (
        .clk(clk), .reset(reset || timed_out), .cart_mode(1'b1),
        .req(probing && req), .wr(1'b0), .addr(addr), .acc(2'b01),
        .wdata(32'd0), .rdata(rdata), .done(bus_done), .busy(),
        .cart_tran_bank2(bank2), .cart_tran_bank2_dir(dir2),
        .cart_tran_bank2_out(out2),
        .cart_tran_bank3(bank3), .cart_tran_bank3_dir(dir3),
        .cart_tran_bank3_out(out3),
        .cart_tran_bank1(bank1), .cart_tran_bank1_dir(dir1),
        .cart_tran_bank1_out(out1),
        .cart_tran_bank0(bank0), .cart_tran_bank0_dir(),
        .cart_tran_pin30(pin30), .cart_tran_pin30_dir(),
        .cart_pin30_pwroff_reset(), .cart_tran_pin31(pin31), .cart_tran_pin31_dir()
    );

    task automatic boot(input string tag, input bit expected);
        integer i;
        begin
            @(negedge clk);
            reset = 1; boot_ready = 0; reads = 0;
            for (i = 0; i < 1024; i = i + 1) image[i] = 8'hff;
            {image['hAC], image['hAD], image['hAE], image['hAF]} = "BPEJ";
            for (i = 0; i < tag.len(); i = i + 1) image['h201+i] = tag[i];
            repeat (4) @(negedge clk);
            reset = 0; boot_ready = 1;
            for (i = 0; i < 25000 && !done; i = i + 1) @(negedge clk);
            if (!done || timed_out || !valid || physical_id !== "BPEJ" || use_cart !== expected)
                $fatal(1, "pin-level probe failed tag=%s id=%h physical=%b timeout=%b",
                       tag, physical_id, use_cart, timed_out);
            if (reads < 2) $fatal(1, "no physical read strobes");
            repeat (4) @(negedge clk);
            if (dir1 || dir2 || dir3 || bank0[6:4] !== 3'b111 || pin30 !== 1'b1)
                $fatal(1, "bus not idle after probe");
            $display("PASS pin-level probe %s (reads=%0d)", tag, reads);
        end
    endtask
    initial begin
        boot("FLASH1M_V103", 1);
        boot("SRAM_V113", 0);
        boot("EEPROM_V124", 0);
        boot("FLASH512_V130", 0);
        $display("cart_save_bus_tb passed");
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "testbench timeout");
    end
endmodule
