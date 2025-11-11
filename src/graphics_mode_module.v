module graphics_mode_module (
    input wire video_clk,           // 25.175 MHz pixel clock
    input wire reset_n,             // Active low reset
    
    // VGA timing inputs
    input wire [9:0] hcount,        // Horizontal pixel counter (0-799)
    input wire [9:0] vcount,        // Vertical line counter (0-524)
    input wire display_active,      // High when in display area
    
    // Mode control
    input wire [7:0] mode_control,  // Video mode and page selection
    
    // Instruction interface from instruction register
    input wire [7:0] instruction,        // Current instruction opcode
    input wire [7:0] arg_data [0:10],    // Argument registers
    input wire instruction_start,        // Pulse to start instruction
    output reg instruction_busy,         // High when instruction executing
    output reg instruction_finished,     // Pulse when instruction complete
    output reg instruction_error,        // High if error occurred
    
    // Video memory interface (dual port BRAM)
    output wire [16:0] video_addr,       // Video memory address (128KB max)
    input wire [7:0] video_data_in,      // Video data read from memory
    output reg [7:0] video_data_out,     // Video data to write to memory
    output reg video_we,                 // Write enable for video memory
    
    // Display renderer address (separate from controller)
    output wire [16:0] display_video_addr,
    input wire [7:0] display_video_data,  // Display data from port B
    
    // Fixed palette interface (16-color modes)
    output reg [3:0] palette_addr,       // Palette address (4-bit color index)
    input wire [11:0] palette_data,      // 12-bit RGB color output

    // Writable palette interface (256-color Mode 4)
    output wire [7:0] writable_palette_addr,   // Palette address (8-bit color index)
    input wire [11:0] writable_palette_data,   // 12-bit RGB color output

    // Writable palette write interface (for SET_PALETTE_ENTRY instruction)
    output reg [7:0] palette_write_addr,       // Palette write address
    output reg [11:0] palette_write_data,      // Palette write data (12-bit RGB)
    output reg palette_write_enable,           // Palette write enable

    // RGB output
    output reg [11:0] rgb_out,           // 12-bit RGB to external DAC
    output reg pixel_valid,              // High when rgb_out is valid

    // Result output for GetPixelAt and GET_PALETTE_ENTRY instructions
    output wire [7:0] result_pixel_data,
    output wire [7:0] result_palette_low,     // GET_PALETTE_ENTRY low byte
    output wire [7:0] result_palette_high     // GET_PALETTE_ENTRY high byte
);

    // Graphics mode parameters
    localparam MODE_640x480x2   = 3'b001;  // 640x480, 2 colors, 2 pages, 1 bit/pixel
    localparam MODE_640x480x4   = 3'b010;  // 640x480, 4 colors, 1 page, 2 bits/pixel
    localparam MODE_320x240x16  = 3'b011;  // 320x240, 16 colors, 2 pages, 4 bits/pixel
    localparam MODE_320x240x64  = 3'b100;  // 320x240, 64 colors, 1 page, 8 bits/pixel
    
    // Instruction opcodes
    localparam WRITE_PIXEL = 8'h10;
    localparam PIXEL_POS = 8'h11;
    localparam WRITE_PIXEL_POS = 8'h12;
    localparam CLEAR_SCREEN = 8'h13;
    localparam GET_PIXEL_AT = 8'h14;
    localparam SET_PALETTE_ENTRY = 8'h20;
    localparam GET_PALETTE_ENTRY = 8'h21;
    
    // Graphics controller state machine states (need 4 bits for additional states)
    localparam IDLE = 4'b0000;
    localparam WRITE_PIXEL_EXEC = 4'b0001;
    localparam PIXEL_POS_EXEC = 4'b0010;
    localparam WRITE_PIXEL_POS_EXEC = 4'b0011;
    localparam CLEAR_SCREEN_EXEC = 4'b0100;
    localparam GET_PIXEL_EXEC = 4'b0101;
    localparam GET_PIXEL_WAIT = 4'b0110;      // Additional wait state for BRAM settling
    localparam GET_PIXEL_READ = 4'b1010;      // Read state for GetPixelAt
    localparam RMW_READ = 4'b0111;
    localparam RMW_READ_WAIT = 4'b1000;       // New state for RMW two-cycle read
    localparam RMW_WRITE = 4'b1001;
    localparam SET_PALETTE_EXEC = 4'b1011;    // Palette write state
    localparam GET_PALETTE_EXEC = 4'b1100;    // Palette read state
    
    reg [3:0] state;
    
    // Mode decode
    wire [2:0] current_mode;
    wire current_page;
    wire working_page;
    
    assign current_mode = mode_control[2:0];
    assign current_page = mode_control[3];     // Active page for display
    assign working_page = mode_control[4];     // Working page for writes
    
    // Graphics controller registers
    reg [15:0] pixel_cursor_x;          // Pixel cursor X position
    reg [15:0] pixel_cursor_y;          // Pixel cursor Y position
    reg [31:0] clear_pixel_counter;     // Counter for clear screen operation
    reg [7:0] rmw_original_data;        // Original data for read-modify-write
    reg [7:0] rmw_new_data;             // New data for read-modify-write
    reg [16:0] rmw_address;             // Address for read-modify-write
    
    // Instruction arguments (latched on instruction_start)
    reg [7:0] inst_arg0, inst_arg1, inst_arg2, inst_arg3, inst_arg4, inst_arg5, inst_arg6;
    
    // Result registers
    reg [7:0] result_pixel_data_reg;
    reg [7:0] result_palette_low_reg;
    reg [7:0] result_palette_high_reg;
    assign result_pixel_data = result_pixel_data_reg;
    assign result_palette_low = result_palette_low_reg;
    assign result_palette_high = result_palette_high_reg;
    
    // Instruction start edge detection (synchronize to video_clk domain)
    reg instruction_start_sync1, instruction_start_sync2, instruction_start_prev;
    wire instruction_start_edge;
    
    // Controller address (internal)
    reg [16:0] video_addr_ctrl_internal;
    
    // Address multiplexing: controller gets priority when writing or during state machine operations
    wire controller_needs_addr;
    reg get_pixel_hold;  // Hold controller address for one extra cycle after GetPixelAt
    assign controller_needs_addr = video_we || (state == GET_PIXEL_EXEC) || (state == GET_PIXEL_WAIT) || (state == GET_PIXEL_READ) || 
                                  (state == RMW_READ) || (state == RMW_READ_WAIT) || (state == RMW_WRITE) || get_pixel_hold;
    assign video_addr = controller_needs_addr ? video_addr_ctrl_internal : display_addr;
    
    // Display renderer gets its own address output  
    assign display_video_addr = display_addr;
    
    // Mode-specific parameters
    reg [15:0] mode_width, mode_height;
    reg [3:0] mode_bits_per_pixel;      // 4 bits to hold value 8
    reg [3:0] mode_pixels_per_byte;     // Changed to 4 bits to hold value 8
    reg mode_has_pages;
    reg [16:0] mode_page_size;
    
    // Calculate mode parameters
    always @(*) begin
        case (current_mode)
            MODE_640x480x2: begin
                mode_width = 640;
                mode_height = 480;
                mode_bits_per_pixel = 1;
                mode_pixels_per_byte = 8;
                mode_has_pages = 1;
                mode_page_size = 38400; // 640*480/8
            end
            MODE_640x480x4: begin
                mode_width = 640;
                mode_height = 480;
                mode_bits_per_pixel = 2;
                mode_pixels_per_byte = 4;
                mode_has_pages = 0;
                mode_page_size = 76800; // 640*480/4
            end
            MODE_320x240x16: begin
                mode_width = 320;
                mode_height = 240;
                mode_bits_per_pixel = 4;
                mode_pixels_per_byte = 2;
                mode_has_pages = 1;
                mode_page_size = 38400; // 320*240/2
            end
            MODE_320x240x64: begin
                mode_width = 320;
                mode_height = 240;
                mode_bits_per_pixel = 8;
                mode_pixels_per_byte = 1;
                mode_has_pages = 0;
                mode_page_size = 76800; // 320*240*1
            end
            default: begin
                mode_width = 640;
                mode_height = 480;
                mode_bits_per_pixel = 1;
                mode_pixels_per_byte = 8;
                mode_has_pages = 0;
                mode_page_size = 38400;
            end
        endcase
    end
    
    // Calculate video memory address for pixel position
    function [16:0] calc_pixel_address;
        input [15:0] x, y;
        input page;
        reg [31:0] pixel_offset;
        reg [16:0] page_offset;
        reg [18:0] byte_offset;         // Increased to 19 bits
        begin
            pixel_offset = y * mode_width + x;
            page_offset = (mode_has_pages && page) ? mode_page_size : 17'h0;
            
            // Convert pixel count to byte count based on pixels per byte
            case (mode_bits_per_pixel)
                1: byte_offset = pixel_offset[18:3]; // 8 pixels per byte, take upper 16 bits
                2: byte_offset = pixel_offset[18:2]; // 4 pixels per byte, take upper 17 bits
                4: byte_offset = pixel_offset[18:1]; // 2 pixels per byte, take upper 18 bits
                8: byte_offset = pixel_offset[18:0]; // 1 pixel per byte, take all 19 bits
                default: byte_offset = pixel_offset[18:3];
            endcase
            
            // Clamp to 17-bit result (may need to increase video memory size)
            calc_pixel_address = page_offset + byte_offset[16:0];
        end
    endfunction
    
    // Calculate bit position within byte for packed pixels
    function [2:0] calc_bit_position;
        input [15:0] x;
        reg [2:0] pixel_in_byte;
        begin
            case (mode_bits_per_pixel)
                4'd1: pixel_in_byte = x[2:0];               // 8 pixels per byte
                4'd2: pixel_in_byte = {x[1:0], 1'b0};       // 4 pixels per byte, 2 bits each
                4'd4: pixel_in_byte = x[0] ? 3'b000 : 3'b100;     // 2 pixels per byte: X odd=0, X even=4
                4'd8: pixel_in_byte = 3'b000;               // 1 pixel per byte
                default: pixel_in_byte = 3'b000;
            endcase
            calc_bit_position = pixel_in_byte;
        end
    endfunction
    
    // Create pixel mask and shift data for read-modify-write
    function [7:0] create_pixel_mask;
        input [2:0] bit_pos;
        input [3:0] bits_per_pixel;     // Changed to 4 bits
        begin
            case (bits_per_pixel)
                4'd1: create_pixel_mask = ~(8'h01 << (7 - bit_pos));
                4'd2: create_pixel_mask = ~(8'h03 << (6 - bit_pos));
                4'd4: create_pixel_mask = ~(8'h0F << (4 - bit_pos));
                4'd8: create_pixel_mask = 8'h00;
                default: create_pixel_mask = 8'hFF;
            endcase
        end
    endfunction
    
    function [7:0] shift_pixel_data;
        input [7:0] pixel_data;
        input [2:0] bit_pos;
        input [3:0] bits_per_pixel;     // Changed to 4 bits
        begin
            case (bits_per_pixel)
                4'd1: shift_pixel_data = (pixel_data & 8'h01) << (7 - bit_pos);
                4'd2: shift_pixel_data = (pixel_data & 8'h03) << (6 - bit_pos);
                4'd4: shift_pixel_data = (pixel_data & 8'h0F) << (4 - bit_pos);
                4'd8: shift_pixel_data = pixel_data;
                default: shift_pixel_data = 8'h00;
            endcase
        end
    endfunction
    
    //========================================
    // GRAPHICS CONTROLLER STATE MACHINE
    //========================================
    
    // Synchronize instruction_start to video_clk domain
    always @(posedge video_clk or negedge reset_n) begin
        if (!reset_n) begin
            instruction_start_sync1 <= 1'b0;
            instruction_start_sync2 <= 1'b0; 
            instruction_start_prev <= 1'b0;
        end else begin
            instruction_start_sync1 <= instruction_start;
            instruction_start_sync2 <= instruction_start_sync1;
            instruction_start_prev <= instruction_start_sync2;
        end
    end
    
    assign instruction_start_edge = instruction_start_sync2 & ~instruction_start_prev;

    // Instruction argument capture and state machine
    always @(posedge video_clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            pixel_cursor_x <= 16'h0000;
            pixel_cursor_y <= 16'h0000;
            instruction_busy <= 1'b0;
            instruction_finished <= 1'b0;
            instruction_error <= 1'b0;
            video_we <= 1'b0;
            video_addr_ctrl_internal <= 17'h00000;
            video_data_out <= 8'h00;
            clear_pixel_counter <= 32'h00000000;
            result_pixel_data_reg <= 8'h00;
            result_palette_low_reg <= 8'h00;
            result_palette_high_reg <= 8'h00;
            get_pixel_hold <= 1'b0;
            palette_write_addr <= 8'h00;
            palette_write_data <= 12'h000;
            palette_write_enable <= 1'b0;
            palette_read_request <= 1'b0;
            palette_read_addr_reg <= 8'h00;
        end else begin
            // Default values
            instruction_finished <= 1'b0;
            instruction_error <= 1'b0;
            video_we <= 1'b0;
            palette_write_enable <= 1'b0;
            palette_read_request <= 1'b0;
            
            // Clear get_pixel_hold after one cycle
            if (get_pixel_hold)
                get_pixel_hold <= 1'b0;
            
            case (state)
                IDLE: begin
                    instruction_busy <= 1'b0;
                    if (instruction_start_edge) begin
                        // Capture arguments
                        inst_arg0 <= arg_data[0];
                        inst_arg1 <= arg_data[1];
                        inst_arg2 <= arg_data[2];
                        inst_arg3 <= arg_data[3];
                        inst_arg4 <= arg_data[4];
                        inst_arg5 <= arg_data[5];
                        inst_arg6 <= arg_data[6];
                        
                        case (instruction)
                            WRITE_PIXEL: begin
                                state <= WRITE_PIXEL_EXEC;
                                instruction_busy <= 1'b1;
                            end
                            PIXEL_POS: begin
                                state <= PIXEL_POS_EXEC;
                                instruction_busy <= 1'b1;
                            end
                            WRITE_PIXEL_POS: begin
                                state <= WRITE_PIXEL_POS_EXEC;
                                instruction_busy <= 1'b1;
                            end
                            CLEAR_SCREEN: begin
                                state <= CLEAR_SCREEN_EXEC;
                                instruction_busy <= 1'b1;
                                clear_pixel_counter <= 32'h00000000;
                            end
                            GET_PIXEL_AT: begin
                                state <= GET_PIXEL_EXEC;
                                instruction_busy <= 1'b1;
                            end
                            SET_PALETTE_ENTRY: begin
                                state <= SET_PALETTE_EXEC;
                                instruction_busy <= 1'b1;
                            end
                            GET_PALETTE_ENTRY: begin
                                state <= GET_PALETTE_EXEC;
                                instruction_busy <= 1'b1;
                            end
                            default: begin
                                instruction_error <= 1'b1;
                            end
                        endcase
                    end
                end
                
                WRITE_PIXEL_EXEC: begin
                    // Check bounds
                    if (pixel_cursor_x >= mode_width || pixel_cursor_y >= mode_height) begin
                        instruction_error <= 1'b1;
                        state <= IDLE;
                    end else if (mode_bits_per_pixel == 8) begin
                        // Direct write for 8-bit mode
                        video_addr_ctrl_internal <= calc_pixel_address(pixel_cursor_x, pixel_cursor_y, working_page);
                        video_data_out <= inst_arg0;
                        video_we <= 1'b1;
                        
                        // Advance cursor
                        if (pixel_cursor_x == mode_width - 1) begin
                            pixel_cursor_x <= 16'h0000;
                            if (pixel_cursor_y == mode_height - 1) begin
                                pixel_cursor_y <= 16'h0000;
                            end else begin
                                pixel_cursor_y <= pixel_cursor_y + 16'd1;
                            end
                        end else begin
                            pixel_cursor_x <= pixel_cursor_x + 16'd1;
                        end
                        
                        state <= IDLE;
                        instruction_finished <= 1'b1;
                    end else begin
                        // Read-modify-write for packed pixel modes
                        rmw_address <= calc_pixel_address(pixel_cursor_x, pixel_cursor_y, working_page);
                        video_addr_ctrl_internal <= calc_pixel_address(pixel_cursor_x, pixel_cursor_y, working_page);
                        state <= RMW_READ;
                    end
                end
                
                PIXEL_POS_EXEC: begin
                    // Set pixel cursor position
                    pixel_cursor_x <= {inst_arg0, inst_arg1}; // High byte, low byte
                    pixel_cursor_y <= {inst_arg2, inst_arg3}; // High byte, low byte
                    state <= IDLE;
                    instruction_finished <= 1'b1;
                end
                
                WRITE_PIXEL_POS_EXEC: begin
                    // Set position and write pixel
                    pixel_cursor_x <= {inst_arg0, inst_arg1}; // High byte, low byte
                    pixel_cursor_y <= {inst_arg2, inst_arg3}; // High byte, low byte
                    
                    // Check bounds
                    if ({inst_arg0, inst_arg1} >= mode_width || {inst_arg2, inst_arg3} >= mode_height) begin
                        instruction_error <= 1'b1;
                        state <= IDLE;
                    end else if (mode_bits_per_pixel == 8) begin
                        // Direct write for 8-bit mode
                        video_addr_ctrl_internal <= calc_pixel_address({inst_arg0, inst_arg1}, {inst_arg2, inst_arg3}, working_page);
                        video_data_out <= inst_arg4;
                        video_we <= 1'b1;
                        
                        // Advance cursor
                        if ({inst_arg0, inst_arg1} == mode_width - 1) begin
                            pixel_cursor_x <= 16'h0000;
                            if ({inst_arg2, inst_arg3} == mode_height - 1) begin
                                pixel_cursor_y <= 16'h0000;
                            end else begin
                                pixel_cursor_y <= {inst_arg2, inst_arg3} + 1;
                            end
                        end else begin
                            pixel_cursor_x <= {inst_arg0, inst_arg1} + 1;
                        end
                        
                        state <= IDLE;
                        instruction_finished <= 1'b1;
                    end else begin
                        // Read-modify-write for packed pixel modes
                        rmw_address <= calc_pixel_address({inst_arg0, inst_arg1}, {inst_arg2, inst_arg3}, working_page);
                        video_addr_ctrl_internal <= calc_pixel_address({inst_arg0, inst_arg1}, {inst_arg2, inst_arg3}, working_page);
                        state <= RMW_READ;
                    end
                end
                
                CLEAR_SCREEN_EXEC: begin
                    // Clear entire screen memory
                    video_addr_ctrl_internal <= (mode_has_pages && working_page) ? 
                                 (mode_page_size + clear_pixel_counter[16:0]) : 
                                 clear_pixel_counter[16:0];
                    video_data_out <= inst_arg0;
                    video_we <= 1'b1;
                    
                    if (clear_pixel_counter == mode_page_size - 1) begin
                        // Done clearing - reset pixel cursor to home position
                        pixel_cursor_x <= 16'h0000;
                        pixel_cursor_y <= 16'h0000;
                        state <= IDLE;
                        instruction_finished <= 1'b1;
                    end else begin
                        clear_pixel_counter <= clear_pixel_counter + 1;
                    end
                end
                
                GET_PIXEL_EXEC: begin
                    // Read pixel at specified position
                    if ({inst_arg0, inst_arg1} >= mode_width || {inst_arg2, inst_arg3} >= mode_height) begin
                        instruction_error <= 1'b1;
                        state <= IDLE;
                    end else begin
                        video_addr_ctrl_internal <= calc_pixel_address({inst_arg0, inst_arg1}, {inst_arg2, inst_arg3}, working_page);
                        state <= GET_PIXEL_WAIT;
                    end
                end
                
                GET_PIXEL_WAIT: begin
                    // Wait one cycle for BRAM to settle with new address
                    state <= GET_PIXEL_READ;
                end
                
                GET_PIXEL_READ: begin
                    // Memory data is now valid, extract the specific pixel
                    case (mode_bits_per_pixel)
                        1: result_pixel_data_reg <= (video_data_in >> (7 - calc_bit_position({inst_arg0, inst_arg1}))) & 8'h01;
                        2: result_pixel_data_reg <= (video_data_in >> (6 - calc_bit_position({inst_arg0, inst_arg1}))) & 8'h03;
                        4: result_pixel_data_reg <= (video_data_in >> (4 - calc_bit_position({inst_arg0, inst_arg1}))) & 8'h0F;
                        8: result_pixel_data_reg <= video_data_in;
                        default: result_pixel_data_reg <= 8'h00;
                    endcase
                    state <= IDLE;
                    instruction_finished <= 1'b1;
                    get_pixel_hold <= 1'b1;  // Hold address for one more cycle
                end
                
                RMW_READ: begin
                    // Set address and wait for memory read
                    state <= RMW_READ_WAIT;
                end
                
                RMW_READ_WAIT: begin
                    // Memory data is now valid, capture and modify it
                    rmw_original_data <= video_data_in;
                    
                    // Calculate the modified byte value
                    // Determine which pixel value to use based on which instruction brought us here
                    if (pixel_cursor_x == {inst_arg0, inst_arg1} && pixel_cursor_y == {inst_arg2, inst_arg3}) begin
                        // This is from WRITE_PIXEL_POS_EXEC
                        rmw_new_data <= (video_data_in & create_pixel_mask(calc_bit_position({inst_arg0, inst_arg1}), mode_bits_per_pixel)) | 
                                       shift_pixel_data(inst_arg4, calc_bit_position({inst_arg0, inst_arg1}), mode_bits_per_pixel);
                    end else begin
                        // This is from WRITE_PIXEL_EXEC
                        rmw_new_data <= (video_data_in & create_pixel_mask(calc_bit_position(pixel_cursor_x[15:0]), mode_bits_per_pixel)) | 
                                       shift_pixel_data(inst_arg0, calc_bit_position(pixel_cursor_x[15:0]), mode_bits_per_pixel);
                    end
                    state <= RMW_WRITE;
                end
                
                RMW_WRITE: begin
                    // Write the modified data back
                    video_addr_ctrl_internal <= rmw_address;
                    video_data_out <= rmw_new_data;
                    video_we <= 1'b1;

                    // Advance cursor
                    if (pixel_cursor_x == mode_width - 1) begin
                        pixel_cursor_x <= 16'h0000;
                        if (pixel_cursor_y == mode_height - 1) begin
                            pixel_cursor_y <= 16'h0000;
                        end else begin
                            pixel_cursor_y <= pixel_cursor_y + 1;
                        end
                    end else begin
                        pixel_cursor_x <= pixel_cursor_x + 1;
                    end

                    state <= IDLE;
                    instruction_finished <= 1'b1;
                end

                SET_PALETTE_EXEC: begin
                    // SET_PALETTE_ENTRY: Write palette entry
                    // inst_arg0: Palette index (0-255)
                    // inst_arg1: RGB low byte (GGGG BBBB)
                    // inst_arg2: RGB high byte (xxxx RRRR)
                    palette_write_addr <= inst_arg0;
                    palette_write_data <= {inst_arg2[3:0], inst_arg1[7:4], inst_arg1[3:0]};  // {RRRR, GGGG, BBBB}
                    palette_write_enable <= 1'b1;
                    state <= IDLE;
                    instruction_finished <= 1'b1;
                end

                GET_PALETTE_EXEC: begin
                    // GET_PALETTE_ENTRY: Read palette entry
                    // inst_arg0: Palette index (0-255)
                    // Set read address and request flag (combinational read in palette module)
                    palette_read_request <= 1'b1;
                    palette_read_addr_reg <= inst_arg0;
                    // The writable_palette has combinational read, so data is available immediately
                    result_palette_low_reg <= writable_palette_data[7:0];   // GGGG BBBB
                    result_palette_high_reg <= {writable_palette_data[11:8], 4'h0};  // RRRR 0000
                    state <= IDLE;
                    instruction_finished <= 1'b1;
                end
            endcase
        end
    end
    
    //========================================
    // GRAPHICS RENDERER
    //========================================
    
    // Display position calculations
    wire [15:0] display_x, display_y;
    reg [15:0] display_x_reg, display_y_reg;
    wire display_in_bounds;
    reg display_in_bounds_reg;
    reg [7:0] display_pixel_value;
    
    // Scale coordinates based on mode
    assign display_x = (current_mode == MODE_320x240x16 || current_mode == MODE_320x240x64) ? 
                      (hcount >> 1) : hcount; // 2x scale for 320x240 modes
    assign display_y = (current_mode == MODE_320x240x16 || current_mode == MODE_320x240x64) ? 
                      (vcount >> 1) : vcount; // 2x scale for 320x240 modes
    
    assign display_in_bounds = (display_x < mode_width) && (display_y < mode_height);
    
    // Pipeline display coordinates for BRAM read delay
    always @(posedge video_clk) begin
        display_x_reg <= display_x;
        display_y_reg <= display_y;
        display_in_bounds_reg <= display_in_bounds;
    end
    
    // Extract pixel value from video memory
    wire [16:0] display_addr;
    assign display_addr = calc_pixel_address(display_x, display_y, current_page);
    
    always @(*) begin
        case (mode_bits_per_pixel)
            1: display_pixel_value = (display_video_data >> (7 - calc_bit_position(display_x_reg))) & 8'h01;
            2: display_pixel_value = (display_video_data >> (6 - calc_bit_position(display_x_reg))) & 8'h03;
            4: display_pixel_value = (display_video_data >> (4 - calc_bit_position(display_x_reg))) & 8'h0F;
            8: display_pixel_value = display_video_data;
            default: display_pixel_value = 8'h00;
        endcase
    end
    
    // Writable palette address multiplexing
    // During GET_PALETTE_ENTRY execution, use instruction argument
    // Otherwise use pixel value for display rendering
    reg palette_read_request;
    reg [7:0] palette_read_addr_reg;
    assign writable_palette_addr = palette_read_request ? palette_read_addr_reg : display_pixel_value[7:0];

    // Generate final RGB output
    always @(posedge video_clk or negedge reset_n) begin
        if (!reset_n) begin
            rgb_out <= 12'h000;
            pixel_valid <= 1'b0;
            palette_addr <= 4'h0;
        end else begin
            pixel_valid <= display_active;

            if (display_active && display_in_bounds_reg) begin
                if (current_mode == MODE_320x240x64) begin
                    // Mode 4: 256-color palette lookup (combinational - zero latency)
                    rgb_out <= writable_palette_data;
                end else begin
                    // Other modes: 16-color palette lookup
                    palette_addr <= display_pixel_value[3:0];
                    rgb_out <= palette_data;
                end
            end else begin
                // Outside display area - output black
                rgb_out <= 12'h000;
            end
        end
    end
    
endmodule
