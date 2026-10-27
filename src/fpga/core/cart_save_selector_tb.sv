`timescale 1ns/1ps
`default_nettype none

module cart_save_selector_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, boot_ready = 0, reset_exit = 0;
    reg power_on = 1, native_adapter = 1;
    wire done, use_cart;

    cart_save_selector dut (
        .clk(clk), .reset(reset), .boot_ready(boot_ready),
        .reset_exit(reset_exit), .cart_power(power_on),
        .native_adapter(native_adapter), .decision_done(done),
        .use_cart_save(use_cart)
    );

    task automatic prepare;
        begin
            @(negedge clk);
            reset = 1; boot_ready = 0; reset_exit = 0;
            power_on = 1; native_adapter = 1;
            repeat (3) @(negedge clk);
            if (done || use_cart) $fatal(1, "backend survived FPGA reset");
            reset = 0;
        end
    endtask

    task automatic check_waiting;
        begin
            repeat (10) @(negedge clk);
            if (done || use_cart) $fatal(1, "selected backend before OS/loader ready");
        end
    endtask

    task automatic finish_case(input bit expected, input string label);
        begin
            repeat (3) @(negedge clk);
            if (!done || use_cart !== expected)
                $fatal(1, "%s: done=%b physical=%b", label, done, use_cart);
            // OS reset/menu activity must never change a running game's backend.
            boot_ready = 0; reset_exit = 0;
            power_on = !power_on; native_adapter = !native_adapter;
            repeat (10) @(negedge clk);
            if (!done || use_cart !== expected) $fatal(1, "backend changed after decision");
            $display("PASS %s", label);
        end
    endtask

    initial begin
        prepare();
        boot_ready = 1;
        check_waiting(); // B1 power notification arrives before actual slot power.
        reset_exit = 1;
        finish_case(1, "loader first: wait for OS Reset Exit, then physical saves");

        prepare();
        reset_exit = 1;
        check_waiting();
        boot_ready = 1;
        finish_case(1, "OS first: wait for loader drain, then physical saves");

        prepare();
        power_on = 0; boot_ready = 1; reset_exit = 1;
        finish_case(0, "OS does not supply cartridge power: SD fallback");

        prepare();
        native_adapter = 0; boot_ready = 1; reset_exit = 1;
        finish_case(0, "unsupported adapter: SD fallback");

        $display("cart_save_selector_tb passed");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "testbench timeout");
    end
endmodule
