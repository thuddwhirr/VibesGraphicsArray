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
    output wire [1:0] red,      // 2-bit red output
    output wire [1:0] green,    // 2-bit green output
    output wire [1:0] blue      // 2-bit blue output
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
    wire [10:0] char_addr_ctrl;
    wire [15:0] char_data_in, char_data_out;
    wire char_we;
    
    wire [16:0] video_addr_ctrl;
    wire [7:0] video_data_in, video_data_out;
    wire video_we;
    
    wire [11:0] font_addr;
    wire [7:0] font_data;
    
    // Palette interface signals
    wire [3:0] palette_addr_text, palette_addr_graphics;
    wire [3:0] palette_addr_read;
    wire [5:0] palette_data_read;
    wire [3:0] palette_addr_write;
    wire [5:0] palette_data_write;
    wire palette_we;
    
    // Multiplex palette address based on active mode
    assign palette_addr_read = video_mode_active ? palette_addr_graphics : palette_addr_text;
    
    // RGB output signals from renderers
    wire [5:0] text_rgb_out, graphics_rgb_out;
    wire text_pixel_valid, graphics_pixel_valid;
    wire [5:0] final_rgb;
    
    // Instruction routing
    wire text_instruction_active, graphics_instruction_active;
    assign text_instruction_active = (instruction >= 8'h00 && instruction <= 8'h0F);
    assign graphics_instruction_active = (instruction >= 8'h10 && instruction <= 8'h1F);
    
    // Instruction status multiplexing
    assign instruction_busy = text_instruction_active ? text_instruction_busy : 
                             graphics_instruction_active ? graphics_instruction_busy : 1'b0;
    assign instruction_finished = text_instruction_active ? text_instruction_finished : 
                                 graphics_instruction_active ? graphics_instruction_finished : 1'b0;
    assign instruction_error = text_instruction_active ? text_instruction_error : 
                              graphics_instruction_active ? graphics_instruction_error : 1'b0;
    
    // Result data multiplexing
    assign final_result_0 = text_instruction_active ? text_result_char_code : 
                           graphics_instruction_active ? graphics_result_pixel_data : 8'h00;
    assign final_result_1 = text_instruction_active ? text_result_char_attr : 8'h00;
    
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
        .mode_control(mode_control)
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
        .palette_addr(palette_addr_text),
        .palette_data(palette_data_read),
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
        .palette_addr(palette_addr_graphics),
        .palette_data(palette_data_read),
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
        .addrb(video_addr_ctrl),  // Use same address for both ports
        .doutb()                  // Not used - single unified address
    );
    
    // Font ROM
    font_rom font_rom_inst (
        .clk(clk_25mhz),
        .addr(font_addr),
        .data(font_data)
    );
    
    // Color Palette
    color_palette palette_inst (
        .clk(clk_25mhz),
        .reset_n(reset_n),
        .read_addr(palette_addr_read),
        .read_data(palette_data_read),
        .write_addr(palette_addr_write),
        .write_data(palette_data_write),
        .write_enable(palette_we)
    );
    
    //========================================
    // VIDEO OUTPUT MULTIPLEXING
    //========================================
    
    // Select RGB output based on current mode
    assign final_rgb = video_mode_active ? graphics_rgb_out : text_rgb_out;
    
    // Convert 6-bit RGB to 2-bit per channel for VGA DAC
    assign red   = final_rgb[5:4];      // Upper 2 bits of 6-bit RGB
    assign green = final_rgb[3:2];      // Middle 2 bits of 6-bit RGB  
    assign blue  = final_rgb[1:0];      // Lower 2 bits of 6-bit RGB
    
    //========================================
    // ADDITIONAL LOGIC
    //========================================
    
    // Future: Add palette write interface for CPU access
    assign palette_addr_write = 4'h0;
    assign palette_data_write = 6'h00;
    assign palette_we = 1'b0;
    
    // Future: Connect result outputs from text/graphics modules
    // This would require adding result output ports to the text/graphics modules
    
    // Memory address routing - removed since modules handle dual-port internally
    // char_addr_rend and video_addr_rend are not needed

endmodule
