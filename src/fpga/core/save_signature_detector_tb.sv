`timescale 1ns/1ps
`default_nettype none
module save_signature_detector_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, valid = 0;
    reg [15:0] data = 0;
    wire f64, f128, other;
    integer cases = 0;
    save_signature_detector dut(clk, reset, valid, data, f64, f128, other);

    task automatic check_tag(input string tag, input bit odd_align,
                             input [2:0] expected);
        string stream;
        integer i;
        begin
            @(negedge clk); reset = 1; valid = 0;
            repeat (2) @(negedge clk);
            reset = 0;
            stream = odd_align ? {"X", tag, "XXX"} : {tag, "XXXX"};
            for (i = 0; i < stream.len() - 1; i = i + 2) begin
                valid = 1;
                data = {stream[i+1], stream[i]};
                @(negedge clk);
            end
            valid = 0;
            if ({f64, f128, other} !== expected)
                $fatal(1, "%s align=%b result=%b expected=%b", tag, odd_align,
                       {f64, f128, other}, expected);
            cases = cases + 1;
        end
    endtask

    initial begin
        check_tag("FLASH_V126", 0, 3'b100);
        check_tag("FLASH_V126", 1, 3'b100);
        check_tag("FLASH512_V130", 0, 3'b100);
        check_tag("FLASH512_V130", 1, 3'b100);
        check_tag("FLASH1M_V103", 0, 3'b010);
        check_tag("FLASH1M_V103", 1, 3'b010);
        check_tag("EEPROM_V124", 0, 3'b001);
        check_tag("EEPROM_V124", 1, 3'b001);
        check_tag("SRAM_V113", 0, 3'b001);
        check_tag("SRAM_V113", 1, 3'b001);
        check_tag("SRAM_F_V102", 0, 3'b001);
        check_tag("SRAM_F_V102", 1, 3'b001);
        check_tag("FLASH is not a library tag", 0, 3'b000);
        check_tag("FLASH1M_V103 SRAM_V113", 0, 3'b011);
        check_tag("FLASH512_V130 FLASH1M_V103", 1, 3'b110);
        $display("save_signature_detector_tb passed (%0d cases)", cases);
        $finish;
    end
endmodule
