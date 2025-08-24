module vga_timing (
    input wire video_clk,       // 25.175 MHz pixel clock
    input wire reset_n,         // Active low reset
    
    // VGA timing outputs
    output reg hsync,           // Horizontal sync
    output reg vsync,           // Vertical sync
    output reg [9:0] hcount,    // Horizontal pixel counter (0-799)
    output reg [9:0] vcount,    // Vertical line counter (0-524)
    
    // Display area flags
    output wire h_display,      // High during horizontal display area
    output wire v_display,      // High during vertical display area
    output wire display_active  // High when both h_display and v_display are active
);

    // VGA 640x480 @ 60Hz timing parameters (25.175 MHz pixel clock)
    // Horizontal timing
    localparam H_DISPLAY    = 640;   // Horizontal display area
    localparam H_FRONT      = 16;    // Horizontal front porch
    localparam H_SYNC       = 96;    // Horizontal sync pulse
    localparam H_BACK       = 48;    // Horizontal back porch
    localparam H_TOTAL      = 800;   // Total horizontal pixels (640+16+96+48)
    
    // Vertical timing  
    localparam V_DISPLAY    = 480;   // Vertical display area
    localparam V_FRONT      = 10;    // Vertical front porch
    localparam V_SYNC       = 2;     // Vertical sync pulse
    localparam V_BACK       = 33;    // Vertical back porch
    localparam V_TOTAL      = 525;   // Total vertical lines (480+10+2+33)
    
    // Sync pulse boundaries
    localparam H_SYNC_START = H_DISPLAY + H_FRONT;           // 656
    localparam H_SYNC_END   = H_DISPLAY + H_FRONT + H_SYNC; // 752
    localparam V_SYNC_START = V_DISPLAY + V_FRONT;           // 490
    localparam V_SYNC_END   = V_DISPLAY + V_FRONT + V_SYNC; // 492
    
    // Horizontal counter and sync generation
    always @(posedge video_clk or negedge reset_n) begin
        if (!reset_n) begin
            hcount <= 10'h000;
            hsync <= 1'b1;     // Sync is normally high (negative polarity)
        end else begin
            // Increment horizontal counter
            if (hcount == H_TOTAL - 1) begin
                hcount <= 10'h000;
            end else begin
                hcount <= hcount + 1;
            end
            
            // Generate horizontal sync (negative polarity)
            if (hcount >= H_SYNC_START && hcount < H_SYNC_END) begin
                hsync <= 1'b0;  // Sync pulse low
            end else begin
                hsync <= 1'b1;  // Sync idle high
            end
        end
    end
    
    // Vertical counter and sync generation
    always @(posedge video_clk or negedge reset_n) begin
        if (!reset_n) begin
            vcount <= 10'h000;
            vsync <= 1'b1;     // Sync is normally high (negative polarity)
        end else begin
            // Increment vertical counter at end of each horizontal line
            if (hcount == H_TOTAL - 1) begin
                if (vcount == V_TOTAL - 1) begin
                    vcount <= 10'h000;
                end else begin
                    vcount <= vcount + 1;
                end
            end
            
            // Generate vertical sync (negative polarity)
            if (vcount >= V_SYNC_START && vcount < V_SYNC_END) begin
                vsync <= 1'b0;  // Sync pulse low
            end else begin
                vsync <= 1'b1;  // Sync idle high
            end
        end
    end
    
    // Display area detection
    assign h_display = (hcount < H_DISPLAY);           // 0-639
    assign v_display = (vcount < V_DISPLAY);           // 0-479
    assign display_active = h_display & v_display;     // Active display area
    
endmodule

