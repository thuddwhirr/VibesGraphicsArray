module vga_card_top (
    // System clocks and reset
    input wire clk_25mhz,       // 25.175 MHz pixel clock
    input wire phi2,            // 1 MHz CPU clock
    input wire reset_n,         // Active low reset
    
    // 6502 CPU Bus Interface
    input wire [3:0] addr,      // 4-bit address bus
    inout wire [7:0] data,      // 8-bit bidirectional data bus
    input wire rw,              // Read/Write signal (1=read, 0=write)
    input wire ce0,             // Chip enable 0
    input wire ce1b,            // Chip enable 1 (active low)
    
    // VGA Output Signals
    output wire hsync,          // Horizontal sync
    output wire vsync,          // Vertical sync
    output wire [3:0] red,      // 4-bit red output (12-bit color)
    output wire [3:0] green,    // 4-bit green output (12-bit color)
    output wire [3:0] blue      // 4-bit blue output (12-bit color)
);

    //========================================
    // INTERNAL SIGNALS
    //========================================
    
    // Data bus signals
    wire [7:0] data_out_internal;
    wire [7:0] data_in_internal;
    wire bus_output_enable;
    
    // Bidirectional data bus control
    assign data_in_internal = data;
    assign data = bus_output_enable ? data_out_internal : 8'hZZ;
    assign bus_output_enable = (ce0 & ~ce1b) & rw;
    
    // VGA timing signals
    wire [9:0] hcount, vcount;
    wire display_active;
    
    // Mode control
    wire [7:0] mode_control;
    wire video_mode_active;     // 0=text mode, 1=graphics mode
    assign video_mode_active = mode_control[7];
    
    // Instruction interface signals
    wire [7:0] instruction;
    wire [7:0] arg_data [0:10];
    wire instruction_start;
    wire text_instruction_busy, graphics_instruction_busy;
    wire text_instruction_finished, graphics_instruction_finished;
    wire text_instruction_error, graphics_instruction_error;
    wire instruction_busy, instruction_finished, instruction_error;
    
    // Result signals from modules
    wire [7:0] text_result_char_code, text_result_char_attr;
    wire [7:0] graphics_result_pixel_data;
    wire [7:0] final_result_0, final_result_1;
    
    // Memory interface signals
    wire [11:0] char_addr_ctrl;  // 12-bit for 2560 character buffer entries
    wire [15:0] char_data_in, char_data_out;
    wire char_we;
    
    wire [16:0] video_addr_ctrl;
    wire [7:0] video_data_in, video_data_out;
    wire video_we;
    
    // Graphics display interface
    wire [16:0] display_video_addr;
    wire [7:0] display_video_data;
    
    wire [11:0] font_addr;
    wire [7:0] font_data;
    
    // Fixed palette interface signals (16-color)
    wire [3:0] palette_addr_text_fg, palette_addr_text_bg, palette_addr_graphics;
    wire [3:0] palette_addr_read_a, palette_addr_read_b;
    wire [11:0] palette_data_read_a, palette_data_read_b;  // 12-bit RGB
    wire [3:0] palette_addr_write;
    wire [11:0] palette_data_write;  // 12-bit RGB
    wire palette_we;

    // Writable palette interface signals (256-color for Mode 4)
    wire [7:0] writable_palette_addr;
    wire [11:0] writable_palette_data;
    wire [7:0] writable_palette_write_addr;
    wire [11:0] writable_palette_write_data;
    wire writable_palette_we;
    wire [7:0] palette_result_low, palette_result_high;
    
    // Multiplex palette addresses based on active mode
    assign palette_addr_read_a = video_mode_active ? palette_addr_graphics : palette_addr_text_fg;
    assign palette_addr_read_b = video_mode_active ? 4'h0 : palette_addr_text_bg; // Graphics mode uses single color for now
    
    // RGB output signals from renderers
    wire [11:0] text_rgb_out, graphics_rgb_out;  // 12-bit RGB
    wire text_pixel_valid, graphics_pixel_valid;
    wire [11:0] final_rgb;  // 12-bit RGB
    
    // Instruction routing
    wire text_instruction_active, graphics_instruction_active, palette_instruction_active;
    assign text_instruction_active = (instruction >= 8'h00 && instruction <= 8'h0F);
    assign graphics_instruction_active = (instruction >= 8'h10 && instruction <= 8'h1F);
    assign palette_instruction_active = (instruction >= 8'h20 && instruction <= 8'h2F);
    
    // Instruction status multiplexing
    assign instruction_busy = text_instruction_active ? text_instruction_busy : 
                             graphics_instruction_active ? graphics_instruction_busy : 1'b0;
    assign instruction_finished = text_instruction_active ? text_instruction_finished : 
                                 graphics_instruction_active ? graphics_instruction_finished : 1'b0;
    assign instruction_error = text_instruction_active ? text_instruction_error : 
                              graphics_instruction_active ? graphics_instruction_error : 1'b0;
    
    // Result data multiplexing
    assign final_result_0 = text_instruction_active ? text_result_char_code :
                           graphics_instruction_active ? graphics_result_pixel_data :
                           palette_instruction_active ? palette_result_low : 8'h00;
    assign final_result_1 = text_instruction_active ? text_result_char_attr :
                           palette_instruction_active ? palette_result_high : 8'h00;
    
    //========================================
    // MODULE INSTANTIATIONS
    //========================================
    
    // VGA Timing Generator
    vga_timing vga_timing_inst (
        .video_clk(clk_25mhz),
        .reset_n(reset_n),
        .hsync(hsync),
        .vsync(vsync),
        .hcount(hcount),
        .vcount(vcount),
        .h_display(),               // Not used at top level
        .v_display(),               // Not used at top level
        .display_active(display_active)
    );
    
    // CPU Interface
    cpu_interface cpu_interface_inst (
        .phi2(phi2),
        .reset_n(reset_n),
        .addr(addr),
        .data_in(data_in_internal),
        .data_out(data_out_internal),
        .rw(rw),
        .ce0(ce0),
        .ce1b(ce1b),
        .instruction(instruction),
        .arg_data(arg_data),
        .instruction_start(instruction_start),
        .instruction_busy(instruction_busy),
        .instruction_finished(instruction_finished),
        .instruction_error(instruction_error),
        .result_0(final_result_0),
        .result_1(final_result_1),
        .mode_control(mode_control),
        .palette_write_addr(writable_palette_write_addr),
        .palette_write_data(writable_palette_write_data),
        .palette_write_enable(writable_palette_we),
        .palette_read_data(writable_palette_data),
        .palette_result_low(palette_result_low),
        .palette_result_high(palette_result_high)
    );
    
    // Text Mode Module
    text_mode_module text_mode_inst (
        .video_clk(clk_25mhz),
        .reset_n(reset_n),
        .hcount(hcount),
        .vcount(vcount),
        .display_active(display_active),
        .instruction(instruction),
        .arg_data(arg_data),
        .instruction_start(instruction_start & text_instruction_active),
        .instruction_busy(text_instruction_busy),
        .instruction_finished(text_instruction_finished),
        .instruction_error(text_instruction_error),
        .char_addr(char_addr_ctrl),
        .char_data_in(char_data_in),
        .char_data_out(char_data_out),
        .char_we(char_we),
        .font_addr(font_addr),
        .font_data(font_data),
        .palette_addr_fg(palette_addr_text_fg),
        .palette_addr_bg(palette_addr_text_bg),
        .palette_data_fg(palette_data_read_a),
        .palette_data_bg(palette_data_read_b),
        .rgb_out(text_rgb_out),
        .pixel_valid(text_pixel_valid),
        .result_char_code(text_result_char_code),
        .result_char_attr(text_result_char_attr)
    );
    
    // Graphics Mode Module
    graphics_mode_module graphics_mode_inst (
        .video_clk(clk_25mhz),
        .reset_n(reset_n),
        .hcount(hcount),
        .vcount(vcount),
        .display_active(display_active),
        .mode_control(mode_control),
        .instruction(instruction),
        .arg_data(arg_data),
        .instruction_start(instruction_start & graphics_instruction_active),
        .instruction_busy(graphics_instruction_busy),
        .instruction_finished(graphics_instruction_finished),
        .instruction_error(graphics_instruction_error),
        .video_addr(video_addr_ctrl),
        .video_data_in(video_data_in),
        .video_data_out(video_data_out),
        .video_we(video_we),
        .display_video_addr(display_video_addr),
        .display_video_data(display_video_data),
        .palette_addr(palette_addr_graphics),
        .palette_data(palette_data_read_a), // 16-color fixed palette
        .writable_palette_addr(writable_palette_addr),
        .writable_palette_data(writable_palette_data), // 256-color writable palette
        .rgb_out(graphics_rgb_out),
        .pixel_valid(graphics_pixel_valid),
        .result_pixel_data(graphics_result_pixel_data)
    );
    
    // Character Buffer Memory
    character_buffer char_buffer_inst (
        .clka(clk_25mhz),
        .clkb(clk_25mhz),
        .reset_n(reset_n),
        .addra(char_addr_ctrl),
        .dina(char_data_out),
        .douta(char_data_in),
        .wea(char_we),
        .addrb(char_addr_ctrl),  // Use same address for both ports
        .doutb()                 // Not used - single unified address
    );
    
    // Video Memory
    video_memory video_mem_inst (
        .clka(clk_25mhz),
        .clkb(clk_25mhz),
        .reset_n(reset_n),
        .addra(video_addr_ctrl),
        .dina(video_data_out),
        .douta(video_data_in),
        .wea(video_we),
        .addrb(display_video_addr),  // Display read address from graphics module
        .doutb(display_video_data)   // Display data to graphics module
    );
    
    // Font ROM
    font_rom font_rom_inst (
        .clk(clk_25mhz),
        .addr(font_addr),
        .data(font_data)
    );
    
    // Fixed Color Palette (16-color, dual-port read)
    color_palette palette_inst (
        .clk(clk_25mhz),
        .reset_n(reset_n),
        .read_addr_a(palette_addr_read_a),
        .read_data_a(palette_data_read_a),
        .read_addr_b(palette_addr_read_b),
        .read_data_b(palette_data_read_b),
        .write_addr(palette_addr_write),
        .write_data(palette_data_write),
        .write_enable(palette_we)
    );

    // Writable Palette (256-color for Mode 4)
    writable_palette writable_palette_inst (
        .clk(clk_25mhz),
        .reset_n(reset_n),
        .read_addr(writable_palette_addr),
        .read_data(writable_palette_data),
        .write_addr(writable_palette_write_addr),
        .write_data(writable_palette_write_data),
        .write_enable(writable_palette_we)
    );

    //========================================
    // VIDEO OUTPUT MULTIPLEXING
    //========================================
    
    // Select RGB output based on current mode
    assign final_rgb = video_mode_active ? graphics_rgb_out : text_rgb_out;

    wire screen_edge;
    assign screen_edge = (hcount==0 || hcount ==639 || vcount==0 || vcount==479) ? 1'b1:1'b0;

    // Output 12-bit RGB directly to VGA DAC (4-4-4 format)
    // Format: final_rgb = {RRRR, GGGG, BBBB}
    assign red   = final_rgb[11:8];     // Red channel (4 bits)
    assign green = final_rgb[7:4];      // Green channel (4 bits)
    assign blue  = final_rgb[3:0];      // Blue channel (4 bits)
    
    //========================================
    // ADDITIONAL LOGIC
    //========================================
    
    // Fixed palette write interface (currently unused - read-only)
    assign palette_addr_write = 4'h0;
    assign palette_data_write = 12'h000;
    assign palette_we = 1'b0;

    // Writable palette write interface - connected to cpu_interface palette instructions

    // Future: Connect result outputs from text/graphics modules
    // This would require adding result output ports to the text/graphics modules
    
    // Memory address routing - removed since modules handle dual-port internally
    // char_addr_rend and video_addr_rend are not needed

endmodule
