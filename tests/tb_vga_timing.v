// Testbench for VGA timing module
`include "test_common.vh"

module tb_vga_timing;

    // Inputs
    reg video_clk;
    reg reset_n;
    
    // Outputs
    wire hsync, vsync;
    wire [9:0] hcount, vcount;
    wire h_display, v_display, display_active;
    
    // Instantiate the Unit Under Test (UUT)
    vga_timing uut (
        .video_clk(video_clk),
        .reset_n(reset_n),
        .hsync(hsync),
        .vsync(vsync),
        .hcount(hcount),
        .vcount(vcount),
        .h_display(h_display),
        .v_display(v_display),
        .display_active(display_active)
    );
    
    // Clock generation - 25.175 MHz
    initial begin
        video_clk = 0;
        forever #(`CLK_25MHZ_PERIOD/2) video_clk = ~video_clk;
    end
    
    // Test variables
    integer h_sync_count = 0;
    integer v_sync_count = 0;
    integer frame_count = 0;
    integer frame_start_time, frame_end_time;
    real frame_period_ns, frame_rate_hz;
    
    // Monitor sync pulses
    always @(negedge hsync) begin
        h_sync_count = h_sync_count + 1;
    end
    
    always @(negedge vsync) begin
        v_sync_count = v_sync_count + 1;
        frame_count = frame_count + 1;
        $display("Frame %d completed at time %t", frame_count, $time);
    end
    
    // Test sequence
    initial begin
        // Initialize VCD dump
        $dumpfile("vga_timing.vcd");
        $dumpvars(0, tb_vga_timing);
        
        $display("Starting VGA Timing Test");
        
        // Initialize Inputs
        reset_n = 0;
        
        // Wait for reset
        `WAIT_NS(100);
        reset_n = 1;
        $display("Reset released at %t", $time);
        
        // Test 1: Basic counter functionality
        $display("Test 1: Basic counter operation");
        `WAIT_CYCLES(video_clk, 1000);
        
        `ASSERT(hcount >= 0 && hcount < 800, "hcount out of range");
        `ASSERT(vcount >= 0 && vcount < 525, "vcount out of range");
        
        // Test 2: Horizontal timing verification
        $display("Test 2: Horizontal timing verification");
        
        // Wait for start of line
        @(posedge video_clk);
        while (hcount != 0) @(posedge video_clk);
        
        // Check display period
        `ASSERT(h_display == 1, "h_display should be high at hcount=0");
        
        // Wait for end of display period
        while (hcount < 640) @(posedge video_clk);
        `ASSERT(h_display == 0, "h_display should be low after hcount=640");
        
        // Check sync timing
        while (hcount < 656) @(posedge video_clk); // Front porch
        `ASSERT(hsync == 1, "hsync should be high during front porch");
        
        while (hcount < 752) @(posedge video_clk); // Sync period
        `ASSERT(hsync == 0, "hsync should be low during sync pulse");
        
        @(posedge video_clk);
        `ASSERT(hsync == 1, "hsync should return high after sync pulse");
        
        // Test 3: Vertical timing verification  
        $display("Test 3: Vertical timing verification");
        
        // Wait for start of frame
        while (vcount != 0) @(posedge video_clk);
        
        // Check display period
        `ASSERT(v_display == 1, "v_display should be high at vcount=0");
        
        // Test 4: Display active signal
        $display("Test 4: Display active signal verification");
        
        // Test various combinations
        while (!(hcount < 640 && vcount < 480)) @(posedge video_clk);
        `ASSERT(display_active == 1, "display_active should be high in active area");
        
        while (!(hcount >= 640 || vcount >= 480)) @(posedge video_clk);
        `ASSERT(display_active == 0, "display_active should be low outside active area");
        
        // Test 5: Complete frame timing
        $display("Test 5: Complete frame timing test");
        
        // Measure one complete frame
        @(negedge vsync);
        frame_start_time = $time;
        @(negedge vsync); 
        frame_end_time = $time;
        
        frame_period_ns = frame_end_time - frame_start_time;
        frame_rate_hz = 1000000000.0 / frame_period_ns;
        
        $display("Frame period: %.2f ns", frame_period_ns);
        $display("Frame rate: %.2f Hz", frame_rate_hz);
        
        // Check if frame rate is approximately 60Hz (allow 1% tolerance)
        `ASSERT(frame_rate_hz > 59.4 && frame_rate_hz < 60.6, "Frame rate should be ~60Hz");
        
        // Test 6: Reset functionality
        $display("Test 6: Reset functionality");
        
        reset_n = 0;
        `WAIT_CYCLES(video_clk, 10);
        
        `ASSERT(hcount == 0, "hcount should be 0 after reset");
        `ASSERT(vcount == 0, "vcount should be 0 after reset");
        `ASSERT(hsync == 1, "hsync should be high after reset");
        `ASSERT(vsync == 1, "vsync should be high after reset");
        
        reset_n = 1;
        `WAIT_CYCLES(video_clk, 10);
        
        $display("All VGA timing tests passed!");
        $display("Horizontal sync pulses: %d", h_sync_count);
        $display("Vertical sync pulses: %d", v_sync_count);
        
        $finish;
    end
    
    // Timeout protection
    initial begin
        #50000000; // 50ms timeout
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule