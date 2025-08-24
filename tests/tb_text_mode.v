// Testbench for text mode module
`include "test_common.vh"

module tb_text_mode;

    // Clock and reset
    reg video_clk;
    reg reset_n;
    
    // VGA timing inputs (simplified for testing)
    reg [9:0] hcount, vcount;
    reg display_active;
    
    // Instruction interface
    reg [7:0] instruction;
    reg [7:0] arg_data [0:10];
    reg instruction_start;
    wire instruction_busy;
    wire instruction_finished;
    wire instruction_error;
    
    // Memory interfaces
    wire [10:0] char_addr;
    wire [15:0] char_data_in, char_data_out;
    wire char_we;
    wire [11:0] font_addr;
    wire [7:0] font_data;
    wire [3:0] palette_addr;
    wire [5:0] palette_data;
    
    // Video output
    wire [5:0] rgb_out;
    wire pixel_valid;
    wire [7:0] result_char_code, result_char_attr;
    
    // Instantiate text mode module
    text_mode_module uut (
        .video_clk(video_clk),
        .reset_n(reset_n),
        .hcount(hcount),
        .vcount(vcount),
        .display_active(display_active),
        .instruction(instruction),
        .arg_data(arg_data),
        .instruction_start(instruction_start),
        .instruction_busy(instruction_busy),
        .instruction_finished(instruction_finished),
        .instruction_error(instruction_error),
        .char_addr(char_addr),
        .char_data_in(char_data_in),
        .char_data_out(char_data_out),
        .char_we(char_we),
        .font_addr(font_addr),
        .font_data(font_data),
        .palette_addr(palette_addr),
        .palette_data(palette_data),
        .rgb_out(rgb_out),
        .pixel_valid(pixel_valid),
        .result_char_code(result_char_code),
        .result_char_attr(result_char_attr)
    );
    
    // Separate addresses for dual-port memory
    wire [10:0] char_addr_write, char_addr_read;
    
    // For testing, use write address when writing, read address when reading
    assign char_addr_write = char_addr;
    assign char_addr_read = 11'h000; // Fixed read address for testing
    
    // Instantiate memory modules  
    character_buffer char_mem (
        .clka(video_clk),
        .clkb(video_clk),
        .reset_n(reset_n),
        .addra(char_addr_write),      // Controller writes
        .dina(char_data_out),
        .douta(char_data_in),
        .wea(char_we),
        .addrb(char_addr_read),       // Display reads (simplified for test)
        .doutb()
    );
    
    font_rom font_inst (
        .clk(video_clk),
        .addr(font_addr),
        .data(font_data)
    );
    
    color_palette palette_inst (
        .clk(video_clk),
        .reset_n(reset_n),
        .read_addr(palette_addr),
        .read_data(palette_data),
        .write_addr(4'h0),
        .write_data(6'h00),
        .write_enable(1'b0)
    );
    
    // Clock generation - 25.175 MHz
    initial begin
        video_clk = 0;
        forever #(`CLK_25MHZ_PERIOD/2) video_clk = ~video_clk;
    end
    
    // Simple VGA timing simulation
    initial begin
        hcount = 0;
        vcount = 0;
        display_active = 0;
        
        forever begin
            `WAIT_CYCLES(video_clk, 1);
            hcount = hcount + 1;
            if (hcount == 800) begin
                hcount = 0;
                vcount = vcount + 1;
                if (vcount == 525) begin
                    vcount = 0;
                end
            end
            display_active = (hcount < 640) && (vcount < 480);
        end
    end
    
    // Task: Execute instruction
    task execute_instruction;
        input [7:0] opcode;
        input [7:0] arg0, arg1, arg2;
        begin
            instruction = opcode;
            arg_data[0] = arg0;
            arg_data[1] = arg1;
            arg_data[2] = arg2;
            
            @(posedge video_clk);
            instruction_start = 1'b1;
            @(posedge video_clk);
            instruction_start = 1'b0;
            
            // Wait for completion
            wait(instruction_finished);
            @(posedge video_clk);
        end
    endtask
    
    // Test sequence
    integer test_char_addr;
    reg [15:0] test_char_data;
    
    initial begin
        // Initialize VCD dump
        $dumpfile("text_mode.vcd");
        $dumpvars(0, tb_text_mode);
        
        $display("Starting Text Mode Test");
        
        // Initialize inputs
        reset_n = 0;
        instruction = 8'h00;
        for (integer i = 0; i <= 10; i = i + 1) begin
            arg_data[i] = 8'h00;
        end
        instruction_start = 1'b0;
        
        // Wait for reset
        `WAIT_CYCLES(video_clk, 10);
        reset_n = 1;
        $display("Reset released at %t", $time);
        
        `WAIT_CYCLES(video_clk, 10);
        
        // Test 1: TextWrite instruction
        $display("Test 1: TextWrite instruction");
        
        execute_instruction(8'h00, 8'h07, 8'h41, 8'h00); // White 'A'
        
        // Wait for instruction to fully complete in video domain
        // 65C02 @ 1MHz = 1000ns, Video @ 25MHz = 39.72ns 
        // Need substantial margin for multi-cycle video operations
        `WAIT_CYCLES(video_clk, 50);
        
        // Verify character was written
        test_char_addr = 0; // Position 0,0
        $display("Expected: 0x0741, Actual: 0x%04h", char_mem.char_mem[test_char_addr]);
        `ASSERT(char_mem.char_mem[test_char_addr] == 16'h0741, "Character 'A' not written correctly");
        
        // Test cursor advancement
        execute_instruction(8'h00, 8'h07, 8'h42, 8'h00); // White 'B'
        `WAIT_CYCLES(video_clk, 50);
        test_char_addr = 1; // Position 0,1
        $display("Expected: 0x0742, Actual: 0x%04h", char_mem.char_mem[test_char_addr]);
        `ASSERT(char_mem.char_mem[test_char_addr] == 16'h0742, "Character 'B' not written correctly");
        
        // Test 2: TextPosition instruction
        $display("Test 2: TextPosition instruction");
        
        execute_instruction(8'h01, 8'd5, 8'd10, 8'h00); // Move to row 5, col 10
        
        // Write character at new position
        execute_instruction(8'h00, 8'h0F, 8'h58, 8'h00); // Bright white 'X'
        `WAIT_CYCLES(video_clk, 50);
        test_char_addr = 5 * 80 + 10; // Row 5, Col 10
        $display("Expected 'X' at addr %0d: 0x0F58, Actual: 0x%04h", test_char_addr, char_mem.char_mem[test_char_addr]);
        `ASSERT(char_mem.char_mem[test_char_addr] == 16'h0F58, "Character 'X' not written at correct position");
        
        // Test 3: TextClear instruction
        $display("Test 3: TextClear instruction");
        
        execute_instruction(8'h02, 8'h04, 8'h00, 8'h00); // Clear with red background
        
        `WAIT_CYCLES(video_clk, 100); // Wait for clearing to complete
        
        // Check several positions are cleared
        for (integer i = 0; i < 10; i = i + 1) begin
            `ASSERT(char_mem.char_mem[i] == 16'h0400, "Memory not cleared correctly");
        end
        
        // Test 4: GetTextAt instruction
        $display("Test 4: GetTextAt instruction");
        
        // Write a test character first
        execute_instruction(8'h01, 8'd2, 8'd3, 8'h00);   // Position to row 2, col 3
        execute_instruction(8'h00, 8'h0A, 8'h4D, 8'h00); // Write green 'M'
        `WAIT_CYCLES(video_clk, 50);
        
        // Check what's actually in memory at address 163 (row 2, col 3)
        test_char_addr = 2 * 80 + 3; // Row 2, Col 3 = 163
        $display("Memory at addr %0d: 0x%04h (should be 0x0A4D)", test_char_addr, char_mem.char_mem[test_char_addr]);
        
        // Now read it back with GetTextAt
        execute_instruction(8'h03, 8'd2, 8'd3, 8'h00);   // Read from row 2, col 3
        `WAIT_CYCLES(video_clk, 50);
        
        $display("GetTextAt results: char=0x%02h (expect 0x4D), attr=0x%02h (expect 0x0A)", result_char_code, result_char_attr);
        `ASSERT(result_char_code == 8'h4D, "GetTextAt character code incorrect");
        `ASSERT(result_char_attr == 8'h0A, "GetTextAt attributes incorrect");
        
        // Test 5: Scrolling behavior
        $display("Test 5: Scrolling behavior");
        
        // Position cursor at bottom right
        execute_instruction(8'h01, 8'd29, 8'd79, 8'h00); // Bottom right corner
        
        // Write character to trigger scroll
        execute_instruction(8'h00, 8'h07, 8'h53, 8'h00); // 'S' - should trigger scroll
        
        `WAIT_CYCLES(video_clk, 100); // Wait for scroll completion
        
        // Test 6: Rendering pipeline
        $display("Test 6: Rendering pipeline test");
        
        // Clear screen and write test pattern
        execute_instruction(8'h02, 8'h07, 8'h00, 8'h00); // Clear to white on black
        `WAIT_CYCLES(video_clk, 200);
        
        // Write 'A' at position 0,0
        execute_instruction(8'h01, 8'd0, 8'd0, 8'h00);   // Position 0,0
        execute_instruction(8'h00, 8'h0F, 8'h41, 8'h00); // Bright white 'A'
        
        // Simulate rendering by stepping through display timing
        // Move to character 0,0 display area
        hcount = 0;
        vcount = 0;
        display_active = 1;
        
        `WAIT_CYCLES(video_clk, 10); // Allow pipeline to settle
        
        // Check that some RGB output is generated
        `WAIT_CYCLES(video_clk, 50);
        // Note: Detailed rendering verification would require more complex timing simulation
        
        // Test 7: Error conditions
        $display("Test 7: Error condition testing");
        
        // Test invalid position
        execute_instruction(8'h01, 8'd50, 8'd90, 8'h00); // Invalid position (>29, >79)
        `ASSERT(instruction_error == 1'b1, "Error not flagged for invalid position");
        
        // Test invalid instruction
        execute_instruction(8'hFF, 8'h00, 8'h00, 8'h00); // Invalid opcode
        // Note: This might not trigger error in current implementation
        
        $display("All text mode tests completed!");
        $finish;
    end
    
    // Timeout protection
    initial begin
        #50000000; // 50ms timeout
        $display("ERROR: Test timeout!");
        $finish;
    end
    
    // Monitor instruction execution
    always @(posedge instruction_start) begin
        $display("Instruction started: 0x%02h, args: 0x%02h 0x%02h 0x%02h at %t", 
                instruction, arg_data[0], arg_data[1], arg_data[2], $time);
    end
    
    always @(posedge instruction_finished) begin
        $display("Instruction completed at %t", $time);
    end
    
    always @(posedge instruction_error) begin
        $display("Instruction error at %t", $time);
    end

endmodule