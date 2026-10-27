`timescale 1ns/1ps
`default_nettype none

module cart_save_selector_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, boot_ready = 0, power_on = 1, native_adapter = 1, play = 0;
    reg [31:0] rom_id = "BPEJ";
    reg rom_valid = 1, rom64 = 0, rom128 = 1, rom_other = 0;
    wire req, probing, done, valid, use_cart, timed_out;
    wire [27:0] addr;
    wire [31:0] physical_id;
    reg response = 0;
    reg [31:0] rdata = 0;
    reg respond = 1;
    reg [7:0] image [0:1023];
    integer requests = 0;

    cart_save_selector #(.TIMEOUT_CYCLES(12), .MAX_SCAN_BYTES(1024)) dut (
        .clk(clk), .reset(reset), .boot_ready(boot_ready), .cart_power(power_on),
        .native_adapter(native_adapter), .play_cartridge(play), .rom_id(rom_id),
        .rom_id_valid(rom_valid), .rom_flash_64(rom64), .rom_flash_128(rom128),
        .rom_other_save(rom_other), .probe_req(req), .probe_addr(addr),
        .probe_response(response), .probe_rdata(rdata), .probing(probing),
        .decision_done(done), .physical_id(physical_id), .physical_id_valid(valid),
        .use_cart_save(use_cart), .probe_timeout(timed_out)
    );

    always @(posedge clk) begin
        response <= 0;
        if (req && !reset) begin
            if (!probing || done) $fatal(1, "probe outside boot ownership");
            if (addr[27:24] != 8 || addr[0] || addr[23:0] > 1022)
                $fatal(1, "invalid read-only ROM probe address %h", addr);
            requests <= requests + 1;
            if (respond) begin
                rdata <= {16'd0, image[addr[9:0] + 1], image[addr[9:0]]};
                response <= 1;
            end
        end
    end

    task automatic prepare(input [31:0] card_id, input string tag);
        integer i;
        begin
            @(negedge clk);
            reset = 1; boot_ready = 0; power_on = 1; native_adapter = 1; play = 0;
            rom_id = "BPEJ"; rom_valid = 1; rom64 = 0; rom128 = 1; rom_other = 0;
            respond = 1; requests = 0;
            for (i = 0; i < 1024; i = i + 1) image[i] = 8'hff;
            for (i = 0; i < 4; i = i + 1) image['hAC+i] = card_id[31-i*8 -: 8];
            // Odd-aligned library tag, crossing multiple halfword requests.
            for (i = 0; i < tag.len(); i = i + 1) image['h181+i] = tag[i];
            repeat (3) @(negedge clk);
            reset = 0;
            repeat (3) @(negedge clk);
            if (req || done || use_cart) $fatal(1, "started before loading finished");
        end
    endtask

    task automatic finish_case(input bit expected, input string label);
        integer i, count;
        begin
            boot_ready = 1;
            for (i = 0; i < 4000 && !done; i = i + 1) @(negedge clk);
            if (!done || use_cart !== expected)
                $fatal(1, "%s: done=%b physical=%b expected=%b", label, done, use_cart, expected);
            count = requests;
            // No hot-switch on a new ROM ID or a late response.
            rom_id = "AXVE";
            repeat (10) @(negedge clk);
            if (use_cart !== expected || req || count != requests)
                $fatal(1, "%s: decision changed or probing continued", label);
            $display("PASS %s (reads=%0d)", label, requests);
        end
    endtask

    initial begin
        prepare("BPEJ", "FLASH1M_V103"); finish_case(1, "matching 128 KiB Flash");
        if (physical_id !== "BPEJ" || !valid) $fatal(1, "game-code byte order");
        prepare("BPEJ", "FLASH512_V130"); rom64 = 1; rom128 = 0;
        finish_case(1, "matching 64 KiB Flash512");
        prepare("BPEJ", "FLASH_V126"); rom64 = 1; rom128 = 0;
        finish_case(1, "matching legacy 64 KiB Flash");
        prepare("BPEE", "FLASH1M_V103"); finish_case(0, "different region/game ID");
        if (requests != 2) $fatal(1, "scanned mismatched card");
        prepare(32'hffffffff, "FLASH1M_V103"); finish_case(0, "no cartridge/open bus");
        prepare(32'd0, "FLASH1M_V103"); finish_case(0, "zero ID");
        prepare("BPEJ", "SRAM_V113"); finish_case(0, "physical SRAM");
        prepare("BPEJ", "SRAM_F_V102"); finish_case(0, "physical SRAM_F");
        prepare("BPEJ", "EEPROM_V124"); finish_case(0, "physical EEPROM");
        prepare("BPEJ", "FLASH512_V130"); finish_case(0, "Flash capacity mismatch");
        prepare("BPEJ", ""); finish_case(0, "unknown physical save type");
        prepare("BPEJ", "FLASH1M_V103");
        {image['h301], image['h302], image['h303], image['h304],
         image['h305], image['h306], image['h307], image['h308]} = "EEPROM_V";
        finish_case(0, "physical non-Flash tag after Flash tag");
        prepare("BPEJ", "FLASH1M_V103");
        {image['h301], image['h302], image['h303], image['h304], image['h305],
         image['h306], image['h307], image['h308], image['h309], image['h30a]} = "FLASH512_V";
        finish_case(0, "physical conflicting Flash capacities");
        prepare("BPEJ", "FLASH1M_V103"); rom128 = 0; rom_other = 1;
        finish_case(0, "SD ROM uses SRAM or EEPROM");
        if (requests != 0) $fatal(1, "probed for non-Flash SD ROM");
        prepare("BPEJ", "FLASH1M_V103"); rom128 = 0;
        finish_case(0, "SD ROM has no recognized save tag");
        prepare("BPEJ", "FLASH1M_V103"); rom_other = 1;
        finish_case(0, "SD ROM has conflicting tags");
        prepare("BPEJ", "FLASH1M_V103"); rom64 = 1;
        finish_case(0, "SD ROM has both Flash capacities");
        prepare("BPEJ", "FLASH1M_V103"); power_on = 0;
        finish_case(0, "unpowered cartridge");
        prepare("BPEJ", "FLASH1M_V103"); native_adapter = 0;
        finish_case(0, "wrong cartridge adapter");
        prepare("BPEJ", "FLASH1M_V103"); rom_valid = 0;
        finish_case(0, "missing SD ROM header");
        prepare("BPEJ", "FLASH1M_V103"); respond = 0;
        finish_case(0, "probe timeout");
        if (!timed_out) $fatal(1, "timeout not signalled");
        prepare("BPEJ", "EEPROM_V124"); play = 1;
        finish_case(0, "Play Cartridge keeps original full-cartridge path");
        if (!valid || requests != 2) $fatal(1, "Play Cartridge ID probe");
        $display("cart_save_selector_tb passed");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "testbench timeout");
    end
endmodule
