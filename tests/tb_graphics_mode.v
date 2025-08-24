// Testbench for graphics mode module with comprehensive bit packing tests
`include "test_common.vh"

module tb_graphics_mode;

    // Clock and reset
    reg video_clk;
    reg reset_n;
    
    // VGA timing inputs (simplified for testing)
    reg [9:0] hcount, vcount;
    reg display_active;
    
    // Mode control
    reg [7:0] mode_control;
    
    // Instruction interface
    reg [7:0] instruction;
    reg [7:0] arg_data [0:10];
    reg instruction_start;
    wire instruction_busy;
    wire instruction_finished;
    wire instruction_error;
    
    // Memory interfaces
    wire [16:0] video_addr;
    wire [7:0] video_data_in, video_data_out;
    wire video_we;
    wire [16:0] display_video_addr;
    wire [7:0] display_video_data;
    wire [3:0] palette_addr;
    wire [5:0] palette_data;
    
    // Video output
    wire [5:0] rgb_out;
    wire pixel_valid;
    wire [7:0] result_pixel_data;
    
    // Instantiate graphics mode module
    graphics_mode_module uut (
        .video_clk(video_clk),
        .reset_n(reset_n),
        .hcount(hcount),
        .vcount(vcount),
        .display_active(display_active),
        .mode_control(mode_control),
        .instruction(instruction),
        .arg_data(arg_data),
        .instruction_start(instruction_start),
        .instruction_busy(instruction_busy),
        .instruction_finished(instruction_finished),
        .instruction_error(instruction_error),
        .video_addr(video_addr),
        .video_data_in(video_data_in),
        .video_data_out(video_data_out),
        .video_we(video_we),
        .display_video_addr(display_video_addr),
        .display_video_data(display_video_data),
        .palette_addr(palette_addr),
        .palette_data(palette_data),
        .rgb_out(rgb_out),
        .pixel_valid(pixel_valid),
        .result_pixel_data(result_pixel_data)
    );
    
    // Instantiate video memory
    video_memory video_mem (
        .clka(video_clk),
        .clkb(video_clk),
        .reset_n(reset_n),
        .addra(video_addr),
        .dina(video_data_out),
        .douta(video_data_in),
        .wea(video_we),
        .addrb(display_video_addr),
        .doutb(display_video_data)
    );
    
    // Instantiate color palette
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
    
    // Task: Execute instruction with substantial delay
    task execute_instruction;
        input [7:0] opcode;
        input [7:0] arg0, arg1, arg2, arg3, arg4, arg5, arg6;
        begin
            instruction = opcode;
            arg_data[0] = arg0;
            arg_data[1] = arg1;
            arg_data[2] = arg2;
            arg_data[3] = arg3;
            arg_data[4] = arg4;
            arg_data[5] = arg5;
            arg_data[6] = arg6;
            
            @(posedge video_clk);
            instruction_start = 1'b1;
            @(posedge video_clk);
            instruction_start = 1'b0;
            
            // Wait for completion
            wait(instruction_finished);
            @(posedge video_clk);
            
            // Extra delay for memory operations (like text mode)
            `WAIT_CYCLES(video_clk, 50);
        end
    endtask
    
    // Task: Set graphics mode
    task set_graphics_mode;
        input [2:0] gfx_mode;
        input active_page;
        input working_page;
        begin
            mode_control = {1'b1, 2'b00, working_page, active_page, gfx_mode}; // Graphics mode active
        end
    endtask
    
    // Task: Write pixel at current cursor
    task write_pixel;
        input [7:0] color;
        begin
            execute_instruction(8'h10, color, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00);
        end
    endtask
    
    // Task: Set pixel position  
    task set_pixel_pos;
        input [15:0] x, y;
        begin
            execute_instruction(8'h11, x[15:8], x[7:0], y[15:8], y[7:0], 8'h00, 8'h00, 8'h00);
        end
    endtask
    
    // Task: Write pixel at specific position
    task write_pixel_at;
        input [15:0] x, y;
        input [7:0] color;
        begin
            execute_instruction(8'h12, x[15:8], x[7:0], y[15:8], y[7:0], color, 8'h00, 8'h00);
        end
    endtask
    
    // Task: Get pixel at position
    task get_pixel_at;
        input [15:0] x, y;
        begin
            execute_instruction(8'h14, x[15:8], x[7:0], y[15:8], y[7:0], 8'h00, 8'h00, 8'h00);
        end
    endtask
    
    // Task: Clear screen
    task clear_screen;
        input [7:0] color;
        begin
            execute_instruction(8'h13, color, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00);
        end
    endtask
    
    // Helper: Check memory byte at address
    function [7:0] read_video_memory;
        input [16:0] addr;
        begin
            read_video_memory = video_mem.video_mem[addr];
        end
    endfunction
    
    // Test sequence
    integer test_addr;
    reg [7:0] test_byte, expected_byte;
    
    initial begin
        // Initialize VCD dump
        $dumpfile("graphics_mode.vcd");
        $dumpvars(0, tb_graphics_mode);
        
        $display("Starting Graphics Mode Comprehensive Test");
        
        // Initialize inputs
        reset_n = 0;
        mode_control = 8'h00;
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
        
        // =================================================================
        // Test 1: Mode 1 - 640x480x2 colors (1 bit/pixel, 8 pixels/byte)
        // =================================================================
        $display("Test 1: Mode 1 - 640x480x2 colors (1 bit/pixel)");
        set_graphics_mode(3'b001, 1'b0, 1'b0); // Mode 1, page 0
        
        clear_screen(8'h00); // Clear to black
        
        // Test bit packing for 1-bit mode
        set_pixel_pos(16'd0, 16'd0); // Position 0,0
        write_pixel(8'h01); // White pixel
        
        // Check that pixel 0 of byte 0 is set
        test_addr = 0; // Address 0
        test_byte = read_video_memory(test_addr);
        expected_byte = 8'b10000000; // Pixel 0 = 1, others = 0
        $display("Mode1 Pixel(0,0)=1: addr=%0d, expected=0x%02h, actual=0x%02h", test_addr, expected_byte, test_byte);
        `ASSERT(test_byte == expected_byte, "Mode 1: Pixel 0 not set correctly");
        
        // Test pixel 1 in same byte
        write_pixel(8'h01); // Should advance cursor to pixel 1
        test_byte = read_video_memory(test_addr);
        expected_byte = 8'b11000000; // Pixels 0,1 = 1
        $display("Mode1 Pixel(1,0)=1: addr=%0d, expected=0x%02h, actual=0x%02h", test_addr, expected_byte, test_byte);
        `ASSERT(test_byte == expected_byte, "Mode 1: Pixel 1 not set correctly");
        
        // Test pixel 7 (last in byte)
        set_pixel_pos(16'd7, 16'd0);
        write_pixel(8'h01);
        test_byte = read_video_memory(test_addr);
        expected_byte = 8'b11000001; // Pixels 0,1,7 = 1
        $display("Mode1 Pixel(7,0)=1: addr=%0d, expected=0x%02h, actual=0x%02h", test_addr, expected_byte, test_byte);
        `ASSERT(test_byte == expected_byte, "Mode 1: Pixel 7 not set correctly");
        
        // Test GetPixelAt for mode 1
        get_pixel_at(16'd0, 16'd0); // Should return 1
        $display("Mode1 GetPixel(0,0): expected=0x01, actual=0x%02h", result_pixel_data);
        `ASSERT(result_pixel_data == 8'h01, "Mode 1: GetPixelAt(0,0) incorrect");
        
        get_pixel_at(16'd2, 16'd0); // Should return 0 (unset pixel)
        $display("Mode1 GetPixel(2,0): expected=0x00, actual=0x%02h", result_pixel_data);
        `ASSERT(result_pixel_data == 8'h00, "Mode 1: GetPixelAt(2,0) incorrect");
        
        // =================================================================
        // Test 2: Mode 2 - 640x480x4 colors (2 bits/pixel, 4 pixels/byte)
        // =================================================================
        $display("Test 2: Mode 2 - 640x480x4 colors (2 bits/pixel)");
        set_graphics_mode(3'b010, 1'b0, 1'b0); // Mode 2
        
        clear_screen(8'h00);
        
        // Test 2-bit pixel packing
        set_pixel_pos(16'd0, 16'd0); // Pixel 0
        write_pixel(8'h03); // Color 3 = 11 binary
        
        test_addr = 0;
        test_byte = read_video_memory(test_addr);
        expected_byte = 8'b11000000; // Pixel 0 = 11, others = 00
        $display("Mode2 Pixel(0,0)=3: addr=%0d, expected=0x%02h, actual=0x%02h", test_addr, expected_byte, test_byte);
        `ASSERT(test_byte == expected_byte, "Mode 2: 2-bit pixel 0 not set correctly");
        
        write_pixel(8'h02); // Color 2 = 10 binary (pixel 1)
        test_byte = read_video_memory(test_addr);
        expected_byte = 8'b11100000; // Pixel 0=11, Pixel 1=10
        $display("Mode2 Pixel(1,0)=2: addr=%0d, expected=0x%02h, actual=0x%02h", test_addr, expected_byte, test_byte);
        `ASSERT(test_byte == expected_byte, "Mode 2: 2-bit pixel 1 not set correctly");
        
        // Test pixel 3 (last in byte)
        set_pixel_pos(16'd3, 16'd0);
        write_pixel(8'h01); // Color 1 = 01 binary
        test_byte = read_video_memory(test_addr);
        expected_byte = 8'b11100001; // Pixels: 11,10,00,01
        $display("Mode2 Pixel(3,0)=1: addr=%0d, expected=0x%02h, actual=0x%02h", test_addr, expected_byte, test_byte);
        `ASSERT(test_byte == expected_byte, "Mode 2: 2-bit pixel 3 not set correctly");
        
        // Test GetPixelAt for mode 2
        get_pixel_at(16'd0, 16'd0); // Should return 3
        $display("Mode2 GetPixel(0,0): expected=0x03, actual=0x%02h", result_pixel_data);
        `ASSERT(result_pixel_data == 8'h03, "Mode 2: GetPixelAt(0,0) incorrect");
        
        get_pixel_at(16'd1, 16'd0); // Should return 2
        $display("Mode2 GetPixel(1,0): expected=0x02, actual=0x%02h", result_pixel_data);
        `ASSERT(result_pixel_data == 8'h02, "Mode 2: GetPixelAt(1,0) incorrect");
        
        // =================================================================
        // Test 3: Mode 3 - 320x240x16 colors (4 bits/pixel, 2 pixels/byte)
        // =================================================================
        $display("Test 3: Mode 3 - 320x240x16 colors (4 bits/pixel)");
        set_graphics_mode(3'b011, 1'b0, 1'b0); // Mode 3
        
        clear_screen(8'h00);
        
        // Test 4-bit pixel packing
        set_pixel_pos(16'd0, 16'd0); // Pixel 0
        write_pixel(8'h0F); // Color 15 = 1111 binary
        
        test_addr = 0;
        test_byte = read_video_memory(test_addr);
        expected_byte = 8'b11110000; // Pixel 0 = 1111, Pixel 1 = 0000
        $display("Mode3 Pixel(0,0)=15: addr=%0d, expected=0x%02h, actual=0x%02h", test_addr, expected_byte, test_byte);
        `ASSERT(test_byte == expected_byte, "Mode 3: 4-bit pixel 0 not set correctly");
        
        write_pixel(8'h05); // Color 5 = 0101 binary (pixel 1)
        test_byte = read_video_memory(test_addr);
        expected_byte = 8'b11110101; // Pixel 0=1111, Pixel 1=0101
        $display("Mode3 Pixel(1,0)=5: addr=%0d, expected=0x%02h, actual=0x%02h", test_addr, expected_byte, test_byte);
        `ASSERT(test_byte == expected_byte, "Mode 3: 4-bit pixel 1 not set correctly");
        
        // Test GetPixelAt for mode 3
        get_pixel_at(16'd0, 16'd0); // Should return 15
        $display("Mode3 GetPixel(0,0): expected=0x0F, actual=0x%02h", result_pixel_data);
        `ASSERT(result_pixel_data == 8'h0F, "Mode 3: GetPixelAt(0,0) incorrect");
        
        get_pixel_at(16'd1, 16'd0); // Should return 5
        $display("Mode3 GetPixel(1,0): expected=0x05, actual=0x%02h", result_pixel_data);
        `ASSERT(result_pixel_data == 8'h05, "Mode 3: GetPixelAt(1,0) incorrect");
        
        // =================================================================
        // Test 4: Mode 4 - 320x240x64 colors (8 bits/pixel, 1 pixel/byte)
        // =================================================================
        $display("Test 4: Mode 4 - 320x240x64 colors (8 bits/pixel)");
        set_graphics_mode(3'b100, 1'b0, 1'b0); // Mode 4
        
        clear_screen(8'h00);
        
        // Test 8-bit direct color (no bit packing)
        set_pixel_pos(16'd0, 16'd0);
        write_pixel(8'h3F); // Full intensity 6-bit RGB: 111111
        
        // Extra delay for Mode 4 dual-port BRAM settling
        `WAIT_CYCLES(video_clk, 100);
        
        test_addr = 0;
        test_byte = read_video_memory(test_addr);
        expected_byte = 8'h3F;
        $display("Mode4 Pixel(0,0)=63: addr=%0d, expected=0x%02h, actual=0x%02h", test_addr, expected_byte, test_byte);
        `ASSERT(test_byte == expected_byte, "Mode 4: 8-bit pixel not set correctly");
        
        set_pixel_pos(16'd1, 16'd0);
        write_pixel(8'h2A); // RGB: 101010
        
        // Extra delay for Mode 4 dual-port BRAM settling
        `WAIT_CYCLES(video_clk, 100);
        
        test_addr = 1;
        test_byte = read_video_memory(test_addr);
        expected_byte = 8'h2A;
        $display("Mode4 Pixel(1,0)=42: addr=%0d, expected=0x%02h, actual=0x%02h", test_addr, expected_byte, test_byte);
        `ASSERT(test_byte == expected_byte, "Mode 4: 8-bit pixel 1 not set correctly");
        
        // Test GetPixelAt for mode 4
        get_pixel_at(16'd0, 16'd0); // Should return 63
        $display("Mode4 GetPixel(0,0): expected=0x3F, actual=0x%02h", result_pixel_data);
        `ASSERT(result_pixel_data == 8'h3F, "Mode 4: GetPixelAt(0,0) incorrect");
        
        // =================================================================
        // Test 5: Boundary conditions and error handling
        // =================================================================
        $display("Test 5: Boundary conditions and error handling");
        
        set_graphics_mode(3'b001, 1'b0, 1'b0); // Back to Mode 1 for boundary tests
        
        // Test pixel position at boundaries
        set_pixel_pos(16'd639, 16'd479); // Max valid position
        write_pixel(8'h01);
        `ASSERT(instruction_error == 1'b0, "Boundary: Max position should not error");
        
        // Test invalid position
        set_pixel_pos(16'd640, 16'd480); // Invalid position
        write_pixel(8'h01);
        `ASSERT(instruction_error == 1'b1, "Boundary: Invalid position should error");
        
        // =================================================================
        // Test 6: WritePixelPos combined operation
        // =================================================================
        $display("Test 6: WritePixelPos combined operation");
        
        set_graphics_mode(3'b010, 1'b0, 1'b0); // Mode 2 for testing
        clear_screen(8'h00);
        
        // Write pixel at specific position in one operation
        write_pixel_at(16'd10, 16'd5, 8'h03); // Color 3 at (10,5)
        
        // Verify it was written correctly
        get_pixel_at(16'd10, 16'd5);
        $display("WritePixelPos(10,5)=3: expected=0x03, actual=0x%02h", result_pixel_data);
        `ASSERT(result_pixel_data == 8'h03, "WritePixelPos: Combined operation failed");
        
        // =================================================================
        // Test 7: Multiple pages (Mode 1 and Mode 3 support pages)
        // =================================================================
        $display("Test 7: Multiple pages testing");
        
        set_graphics_mode(3'b001, 1'b0, 1'b0); // Mode 1, display page 0, work page 0
        clear_screen(8'h00);
        set_pixel_pos(16'd0, 16'd0);
        write_pixel(8'h01); // Write to page 0
        
        set_graphics_mode(3'b001, 1'b0, 1'b1); // Mode 1, display page 0, work page 1
        set_pixel_pos(16'd0, 16'd0);
        write_pixel(8'h01); // Write to page 1
        
        // Switch back to page 0 and verify
        set_graphics_mode(3'b001, 1'b0, 1'b0); // Back to page 0
        get_pixel_at(16'd0, 16'd0);
        $display("Page 0 pixel: expected=0x01, actual=0x%02h", result_pixel_data);
        `ASSERT(result_pixel_data == 8'h01, "Pages: Page 0 data lost");
        
        $display("All graphics mode tests completed successfully!");
        $finish;
    end
    
    // Timeout protection
    initial begin
        #200000000; // 200ms timeout
        $display("ERROR: Graphics mode test timeout!");
        $finish;
    end
    
    // Monitor instruction execution
    always @(posedge instruction_start) begin
        $display("Graphics instruction started: 0x%02h at %t", instruction, $time);
    end
    
    always @(posedge instruction_finished) begin
        $display("Graphics instruction completed at %t", $time);
    end
    
    always @(posedge instruction_error) begin
        $display("Graphics instruction error at %t", $time);
    end

endmodule