`default_nettype none

// Read-only, boot-time game-code probe. The decision is immutable until reset:
// never switch a running game from a physical save to an unrelated SD save.
module cart_save_selector #(
    parameter integer TIMEOUT_CYCLES = 65535,
    parameter integer MAX_SCAN_BYTES = 33554432
) (
    input wire clk,
    input wire reset,
    input wire boot_ready,
    input wire cart_power,
    input wire native_adapter,
    input wire play_cartridge,
    input wire [31:0] rom_id,
    input wire rom_id_valid,
    input wire rom_flash_64,
    input wire rom_flash_128,
    input wire rom_other_save,
    output wire probe_req,
    output wire [27:0] probe_addr,
    input wire probe_response,
    input wire [31:0] probe_rdata,
    output wire probing,
    output reg decision_done,
    output reg [31:0] physical_id,
    output reg physical_id_valid,
    output reg use_cart_save,
    output reg probe_timeout
);
    localparam IDLE = 4'd0, READ0 = 4'd1, WAIT0 = 4'd2,
               READ1 = 4'd3, WAIT1 = 4'd4, DECIDE = 4'd5, DONE = 4'd6,
               SCAN_REQ = 4'd7, SCAN_WAIT = 4'd8, SCAN_CHECK = 4'd9;
    localparam [24:0] LAST_SCAN_ADDR = 25'(MAX_SCAN_BYTES - 2);
    reg [3:0] state;
    reg [15:0] first_half;
    reg [31:0] timeout_count;
    reg [24:0] scan_addr;
    wire cart_flash_64, cart_flash_128, cart_other_save;
    wire rom_is_flash = (rom_flash_64 ^ rom_flash_128) && !rom_other_save;

    save_signature_detector cart_signature (
        .clk(clk),
        .reset(reset || state == IDLE),
        .word_valid(state == SCAN_WAIT && probe_response),
        .word_data(probe_rdata[15:0]),
        .flash_64(cart_flash_64),
        .flash_128(cart_flash_128),
        .other_save(cart_other_save)
    );

    function automatic valid_code(input [31:0] code);
        integer i;
        reg [7:0] c;
        begin
            valid_code = 1'b1;
            for (i = 0; i < 4; i = i + 1) begin
                c = code[i*8 +: 8];
                if (!((c >= "A" && c <= "Z") || (c >= "0" && c <= "9")))
                    valid_code = 1'b0;
            end
        end
    endfunction

    assign probe_req = state == READ0 || state == READ1 || state == SCAN_REQ;
    assign probe_addr = (state == SCAN_REQ || state == SCAN_WAIT || state == SCAN_CHECK) ?
                        (28'h8000000 | {3'd0, scan_addr}) :
                        ((state == READ1 || state == WAIT1) ? 28'h80000AE : 28'h80000AC);
    assign probing = state != IDLE && state != DONE;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            first_half <= 16'd0;
            timeout_count <= 32'd0;
            scan_addr <= 25'd0;
            decision_done <= 1'b0;
            physical_id <= 32'd0;
            physical_id_valid <= 1'b0;
            use_cart_save <= 1'b0;
            probe_timeout <= 1'b0;
        end else begin
            case (state)
                IDLE: if (boot_ready) begin
                    if (!cart_power || !native_adapter ||
                        (!play_cartridge && (!rom_id_valid || !rom_is_flash))) begin
                        decision_done <= 1'b1;
                        state <= DONE;
                    end else begin
                        state <= READ0;
                    end
                end
                READ0: begin
                    timeout_count <= 32'd0;
                    state <= WAIT0;
                end
                READ1: begin
                    timeout_count <= 32'd0;
                    state <= WAIT1;
                end
                SCAN_REQ: begin
                    timeout_count <= 32'd0;
                    state <= SCAN_WAIT;
                end
                WAIT0, WAIT1, SCAN_WAIT: begin
                    if (probe_response) begin
                        if (state == WAIT0) begin
                            first_half <= probe_rdata[15:0];
                            state <= READ1;
                        end else if (state == WAIT1) begin
                            physical_id <= {first_half[7:0], first_half[15:8],
                                            probe_rdata[7:0], probe_rdata[15:8]};
                            state <= DECIDE;
                        end else begin
                            state <= SCAN_CHECK;
                        end
                    end else if (!cart_power || timeout_count == TIMEOUT_CYCLES - 1) begin
                        probe_timeout <= 1'b1;
                        decision_done <= 1'b1;
                        state <= DONE;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                DECIDE: begin
                    physical_id_valid <= valid_code(physical_id);
                    if (!play_cartridge && cart_power && native_adapter &&
                        rom_id_valid && rom_is_flash && valid_code(rom_id) &&
                        valid_code(physical_id) && physical_id == rom_id) begin
                        state <= SCAN_REQ;
                    end else begin
                        decision_done <= 1'b1;
                        state <= DONE;
                    end
                end
                SCAN_CHECK: begin
                    if (!cart_power || cart_other_save || (cart_flash_64 && cart_flash_128)) begin
                        decision_done <= 1'b1;
                        state <= DONE;
                    end else if (scan_addr >= LAST_SCAN_ADDR) begin
                        // Scan the entire ROM window before accepting Flash:
                        // a later SRAM/EEPROM or conflicting Flash tag rejects it.
                        // Require matching capacity too: a hacked ROM must not
                        // address bank 1 on a physical 64 KiB Flash cartridge.
                        use_cart_save <= (cart_flash_64 || cart_flash_128) &&
                                         cart_flash_64 == rom_flash_64 &&
                                         cart_flash_128 == rom_flash_128;
                        decision_done <= 1'b1;
                        state <= DONE;
                    end else begin
                        scan_addr <= scan_addr + 25'd2;
                        state <= SCAN_REQ;
                    end
                end
                DONE: ;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
