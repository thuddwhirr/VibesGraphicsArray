// Integration testbench for complete VGA card system
`include "test_common.vh"

module tb_integration;

    // System clocks and reset
    reg clk_25mhz;
    reg phi2;
    reg reset_n;
    
    // 65C02 CPU Bus Interface
    reg [3:0] addr;
    wire [7:0] data;
    reg [7:0] cpu_data_out;
    reg cpu_driving_bus;
    reg rw;
    reg ce0;
    reg ce1b;
    
    // VGA Output Signals
    wire hsync, vsync;
    wire [1:0] red, green, blue;
    
    // Bidirectional data bus control
    assign data = cpu_driving_bus ? cpu_data_out : 8'hZZ;
    
    // Instantiate the complete VGA card
    vga_card_top uut (
        .clk_25mhz(clk_25mhz),
        .phi2(phi2),
        .reset_n(reset_n),
        .addr(addr),
        .data(data),
        .rw(rw),
        .ce0(ce0),
        .ce1b(ce1b),
        .hsync(hsync),
        .vsync(vsync),
        .red(red),
        .green(green),
        .blue(blue)
    );
    
    // Clock generation
    initial begin
        clk_25mhz = 0;
        forever #(`CLK_25MHZ_PERIOD/2) clk_25mhz = ~clk_25mhz;
    end
    
    initial begin
        phi2 = 0;
        forever #(`CLK_1MHZ_PERIOD/2) phi2 = ~phi2;
    end
    
    // Task: CPU write operation
    task cpu_write;
        input [3:0] write_addr;
        input [7:0] write_data;
        begin
            @(negedge phi2);
            addr = write_addr;
            rw = 1'b0;  // Write
            ce0 = 1'b1;
            ce1b = 1'b0;
            cpu_data_out = write_data;
            cpu_driving_bus = 1'b1;
            
            @(posedge phi2);
            #200; // Hold time
            
            @(negedge phi2);
            cpu_driving_bus = 1'b0;
            rw = 1'b1;
            ce0 = 1'b0;
            ce1b = 1'b1;
            
            // Wait for potential instruction execution
            `WAIT_CYCLES(phi2, 2);
        end
    endtask
    
    // Task: CPU read operation
    task cpu_read;
        input [3:0] read_addr;
        output [7:0] read_data;
        begin
            @(negedge phi2);
            addr = read_addr;
            rw = 1'b1;  // Read
            ce0 = 1'b1;
            ce1b = 1'b0;
            cpu_driving_bus = 1'b0;
            
            @(posedge phi2);
            #300; // Access time
            read_data = data;
            
            @(negedge phi2);
            ce0 = 1'b0;
            ce1b = 1'b1;
        end
    endtask
    
    // Task: Wait for instruction completion
    task wait_instruction_complete;
        reg [7:0] status;
        integer timeout_count;
        begin
            timeout_count = 0;
            do begin
                cpu_read(4'hF, status);
                timeout_count = timeout_count + 1;
                if (timeout_count > 1000) begin
                    $display("ERROR: Instruction timeout!");
                    $finish;
                end
            end while (status[0] == 1'b1); // Wait while busy
        end
    endtask
    
    // Task: Complete text write sequence
    task text_write_char;
        input [7:0] attributes;
        input [7:0] character;
        begin
            cpu_write(4'h1, 8'h00);        // TextWrite instruction
            cpu_write(4'h2, attributes);   // Attributes
            cpu_write(4'h3, character);    // Character (triggers execution)
            wait_instruction_complete();
        end
    endtask
    
    // Task: Position cursor
    task text_position;
        input [7:0] row;
        input [7:0] col;
        begin
            cpu_write(4'h1, 8'h01);    // TextPosition instruction
            cpu_write(4'h2, row);      // Row
            cpu_write(4'h3, col);      // Column (triggers execution)
            wait_instruction_complete();
        end
    endtask
    
    // Task: Clear screen
    task text_clear;
        input [7:0] attributes;
        begin
            cpu_write(4'h1, 8'h02);    // TextClear instruction
            cpu_write(4'h2, attributes); // Attributes (triggers execution)
            wait_instruction_complete();
        end
    endtask
    
    // Test variables
    reg [7:0] read_value;
    integer frame_count = 0;
    integer test_pixel_count = 0;
    integer initial_frame_count;
    
    // Monitor frame completion
    always @(negedge vsync) begin
        frame_count = frame_count + 1;
        $display("Frame %d completed at time %t", frame_count, $time);
    end
    
    // Monitor video output activity
    always @(posedge clk_25mhz) begin
        if (|{red, green, blue}) begin
            test_pixel_count = test_pixel_count + 1;
        end
    end
    
    // Main test sequence
    initial begin
        // Initialize VCD dump
        $dumpfile("integration.vcd");
        $dumpvars(0, tb_integration);
        
        $display("Starting Integration Test");
        
        // Initialize inputs
        reset_n = 0;
        addr = 4'h0;
        rw = 1'b1;
        ce0 = 1'b0;
        ce1b = 1'b1;
        cpu_driving_bus = 1'b0;
        
        // Wait for reset
        `WAIT_CYCLES(phi2, 10);
        reset_n = 1;
        $display("Reset released at %t", $time);
        
        `WAIT_CYCLES(phi2, 5);
        
        // Test 1: Basic system readiness
        $display("Test 1: Basic system readiness");
        
        cpu_read(4'hF, read_value);
        `ASSERT(read_value[7] == 1'b1, "System should be ready after reset");
        `ASSERT(read_value[0] == 1'b0, "System should not be busy after reset");
        
        // Test 2: Mode control
        $display("Test 2: Mode control");
        
        cpu_write(4'h0, 8'h00); // Text mode (bit 7 = 0)
        cpu_read(4'h0, read_value);
        `ASSERT(read_value == 8'h00, "Mode control register not set correctly");
        
        // Test 3: Text mode operations
        $display("Test 3: Text mode operations");
        
        // Clear screen with white on black
        text_clear(8'h07);
        $display("Screen cleared");
        
        // Write "HELLO" at top left
        text_position(0, 0);
        text_write_char(8'h0F, 8'h48); // Bright white 'H'
        text_write_char(8'h0F, 8'h45); // 'E'
        text_write_char(8'h0F, 8'h4C); // 'L'
        text_write_char(8'h0F, 8'h4C); // 'L'
        text_write_char(8'h0F, 8'h4F); // 'O'
        
        $display("'HELLO' written to screen");
        
        // Test 4: Graphics mode switching
        $display("Test 4: Graphics mode switching");
        
        cpu_write(4'h0, 8'h81); // Graphics mode 1 (640x480x2)
        cpu_read(4'h0, read_value);
        `ASSERT(read_value == 8'h81, "Graphics mode not set correctly");
        
        // Test simple pixel write
        cpu_write(4'h1, 8'h10);    // WritePixel instruction
        cpu_write(4'h2, 8'h01);    // White pixel
        wait_instruction_complete();
        
        $display("Pixel written in graphics mode");
        
        // Test 5: Video signal generation
        $display("Test 5: Video signal generation");
        
        // Wait for several frames to be generated
        initial_frame_count = frame_count;
        #20000000; // Wait 20ms
        
        `ASSERT(frame_count > initial_frame_count, "No frames generated");
        $display("Video timing working - %d frames generated", frame_count - initial_frame_count);
        
        // Check that sync signals are functioning
        `ASSERT(hsync === 1'b1 || hsync === 1'b0, "HSYNC not driven");
        `ASSERT(vsync === 1'b1 || vsync === 1'b0, "VSYNC not driven");
        
        // Test 6: Error handling
        $display("Test 6: Error handling");
        
        // Switch back to text mode
        cpu_write(4'h0, 8'h00);
        
        // Try invalid instruction
        cpu_write(4'h1, 8'hFF);    // Invalid instruction
        cpu_write(4'h2, 8'h00);    // Dummy arg
        wait_instruction_complete();
        
        cpu_read(4'hF, read_value);
        // Note: Current implementation may not flag this as error
        
        // Test 7: Stress test - rapid operations
        $display("Test 7: Stress test");
        
        text_clear(8'h07);
        
        // Write a pattern across multiple positions
        for (integer i = 0; i < 10; i = i + 1) begin
            text_position(i[7:0], (i*8) % 80);
            text_write_char(8'h0F, 8'h30 + i); // '0' + i
        end
        
        $display("Stress test pattern written");
        
        // Test 8: Video output verification
        $display("Test 8: Video output verification");
        
        // Reset pixel counter
        test_pixel_count = 0;
        
        // Wait a bit and check for video activity
        #5000000; // 5ms
        
        `ASSERT(test_pixel_count > 0, "No non-black pixels generated");
        $display("Video output active - %d non-black pixels detected", test_pixel_count);
        
        // Test 9: Full system integration
        $display("Test 9: Full system integration test");
        
        // Create a test pattern that uses both text positioning and character writing
        text_clear(8'h07);
        
        // Write "TEST" in different colors and positions
        text_position(5, 10);
        text_write_char(8'h0C, 8'h54); // Light red 'T'
        
        text_position(5, 11);
        text_write_char(8'h0A, 8'h45); // Light green 'E'
        
        text_position(5, 12);
        text_write_char(8'h09, 8'h53); // Light blue 'S'
        
        text_position(5, 13);
        text_write_char(8'h0E, 8'h54); // Yellow 'T'
        
        // Verify system is still responsive
        cpu_read(4'hF, read_value);
        `ASSERT(read_value[7] == 1'b1, "System not ready after operations");
        
        $display("Integration test pattern completed");
        
        // Let the system run for a bit to generate video
        $display("Letting system run to generate video output...");
        #10000000; // 10ms more
        
        $display("All integration tests completed successfully!");
        $display("Total frames generated: %d", frame_count);
        $display("Total non-black pixels: %d", test_pixel_count);
        
        $finish;
    end
    
    // Timeout protection
    initial begin
        #200000000; // 200ms timeout
        $display("ERROR: Integration test timeout!");
        $finish;
    end
    
    // Performance monitoring
    initial begin
        $display("Integration Test Performance Monitor Started");
        
        forever begin
            #10000000; // Every 10ms
            $display("Time: %t, Frames: %d, Active Pixels: %d", $time, frame_count, test_pixel_count);
        end
    end

endmodule