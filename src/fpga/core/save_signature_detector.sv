`default_nettype none

// Nintendo save-library tags, at either byte alignment. This is deliberately
// read-only: Flash ID commands would corrupt SRAM on a non-Flash cartridge.
module save_signature_detector (
    input wire clk,
    input wire reset,
    input wire word_valid,
    input wire [15:0] word_data,
    output reg flash_64,
    output reg flash_128,
    output reg other_save
);
    reg [79:0] history;
    wire [79:0] odd_window = {history[71:0], word_data[7:0]};
    wire [79:0] even_window = {history[63:0], word_data[7:0], word_data[15:8]};

    function automatic is_flash64(input [79:0] w);
        is_flash64 = w[55:0] == "FLASH_V" || w == "FLASH512_V";
    endfunction
    function automatic is_flash128(input [79:0] w);
        is_flash128 = w[71:0] == "FLASH1M_V";
    endfunction
    function automatic is_other(input [79:0] w);
        is_other = w[63:0] == "EEPROM_V" || w[47:0] == "SRAM_V" ||
                   w[63:0] == "SRAM_F_V";
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            history <= 80'd0;
            flash_64 <= 1'b0;
            flash_128 <= 1'b0;
            other_save <= 1'b0;
        end else if (word_valid) begin
            history <= even_window;
            if (is_flash64(odd_window) || is_flash64(even_window)) flash_64 <= 1'b1;
            if (is_flash128(odd_window) || is_flash128(even_window)) flash_128 <= 1'b1;
            if (is_other(odd_window) || is_other(even_window)) other_save <= 1'b1;
        end
    end
endmodule
