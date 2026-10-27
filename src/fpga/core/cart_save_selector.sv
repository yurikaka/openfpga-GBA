`default_nettype none

// Temporary hardware test mode: the operator supplies a 128 KiB Flash ROM
// and cartridge. Do not read the physical ROM or inspect save library tags.
// The OS power notification describes future power, not a power-good signal:
// wait for Reset Exit as well as the fully drained loader before deciding.
// Keep the backend immutable until FPGA reload.
module cart_save_selector (
    input wire clk,
    input wire reset,
    input wire boot_ready,
    input wire reset_exit,
    input wire cart_power,
    input wire native_adapter,
    output reg decision_done,
    output reg use_cart_save
);
    always @(posedge clk) begin
        if (reset) begin
            decision_done <= 1'b0;
            use_cart_save <= 1'b0;
        end else if (!decision_done && boot_ready && reset_exit) begin
            decision_done <= 1'b1;
            use_cart_save <= cart_power && native_adapter;
        end
    end
endmodule
