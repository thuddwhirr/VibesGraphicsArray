module text_mode_module (
    input wire video_clk,           // 25.175 MHz pixel clock
    input wire reset_n,             // Active low reset
    
    // VGA timing inputs
    input wire [9:0] hcount,        // Horizontal pixel counter (0-799)
    input wire [9:0] vcount,        // Vertical line counter (0-524)
    input wire display_active,      // High when in display area
    
    // Instruction interface from instruction register
    input wire [7:0] instruction,        // Current instruction opcode
    input wire [7:0] arg_data [0:10],    // Argument registers
    input wire instruction_start,        // Pulse to start instruction
    output reg instruction_busy,         // High when instruction executing
    output reg instruction_finished,     // Pulse when instruction complete
    output reg instruction_error,        // High if error occurred
    
    // Character buffer interface (dual port BRAM)
    output wire [10:0] char_addr,    // Character memory address (unified)
    input wire [15:0] char_data_in, // Character data read from memory
    output reg [15:0] char_data_out,// Character data to write to memory
    output reg char_we,             // Write enable for character memory
    
    // Font ROM interface
    output reg [11:0] font_addr,    // Font ROM address
    input wire [7:0] font_data,     // 8-bit font row data
    
    // Palette interface
    output reg [3:0] palette_addr,  // Palette address (4-bit color index)
    input wire [5:0] palette_data,  // 6-bit RGB color output
    
    // RGB output
    output reg [5:0] rgb_out,       // 6-bit RGB to external DAC
    output reg pixel_valid,         // High when rgb_out is valid
    
    // Result outputs for GetTextAt instruction
    output wire [7:0] result_char_code,
    output wire [7:0] result_char_attr
);

    // Text mode parameters
    localparam CHAR_WIDTH = 8;      // 8 pixels per character
    localparam CHAR_HEIGHT = 16;    // 16 pixels per character
    localparam CHARS_PER_ROW = 80;  // 80 characters per row
    localparam VISIBLE_ROWS = 30;   // 30 visible rows
    localparam TOTAL_ROWS = 31;     // 30 visible + 1 scroll buffer
    
    // Instruction opcodes
    localparam TEXT_WRITE = 8'h00;
    localparam TEXT_POSITION = 8'h01;
    localparam TEXT_CLEAR = 8'h02;
    localparam GET_TEXT_AT = 8'h03;
    
    // Text controller state machine states
    localparam IDLE = 3'b000;
    localparam TEXT_WRITE_EXEC = 3'b001;
    localparam TEXT_POSITION_EXEC = 3'b010;
    localparam TEXT_CLEAR_EXEC = 3'b011;
    localparam GET_TEXT_EXEC = 3'b100;
    localparam GET_TEXT_READ = 3'b101;  // New state for memory read timing
    localparam SCROLL_EXEC = 3'b110;    // Moved to accommodate new state
    
    reg [2:0] state;
    
    // Text controller registers
    reg [6:0] cursor_col;           // Cursor column (0-79)
    reg [4:0] cursor_row;           // Cursor row (0-29)
    reg [4:0] scroll_offset;        // Current scroll position (0-30)
    reg [4:0] clear_row_counter;    // Counter for clearing operations
    reg [6:0] clear_col_counter;    // Counter for clearing operations
    
    // Instruction arguments (latched on instruction_start)
    reg [7:0] inst_arg0, inst_arg1, inst_arg2;
    
    // Result registers
    reg [7:0] result_char_code_reg;
    reg [7:0] result_char_attr_reg;
    
    // Connect result outputs
    assign result_char_code = result_char_code_reg;
    assign result_char_attr = result_char_attr_reg;
    
    // Address management - separate controller and display addresses
    reg [10:0] char_addr_ctrl_internal;  // Internal controller address
    reg [10:0] disp_char_addr;          // Display address
    
    // Multiplex address based on whether we're writing OR doing GetTextAt read
    wire controller_needs_addr = char_we || (state == GET_TEXT_EXEC) || (state == GET_TEXT_READ);
    assign char_addr = controller_needs_addr ? char_addr_ctrl_internal : disp_char_addr;
    
    //========================================
    // TEXT CONTROLLER STATE MACHINE
    //========================================
    
    // Instruction argument capture and state machine
    always @(posedge video_clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            cursor_col <= 7'h00;
            cursor_row <= 5'h00;
            scroll_offset <= 5'h00;
            instruction_busy <= 1'b0;
            instruction_finished <= 1'b0;
            instruction_error <= 1'b0;
            char_we <= 1'b0;
            char_data_out <= 16'h0000;
            clear_row_counter <= 5'h00;
            clear_col_counter <= 7'h00;
            char_addr_ctrl_internal <= 11'h000;
        end else begin
            // Default values
            instruction_finished <= 1'b0;
            instruction_error <= 1'b0;
            char_we <= 1'b0;
            
            case (state)
                IDLE: begin
                    instruction_busy <= 1'b0;
                    if (instruction_start) begin
                        // Capture arguments
                        inst_arg0 <= arg_data[0];
                        inst_arg1 <= arg_data[1];
                        inst_arg2 <= arg_data[2];
                        
                        case (instruction)
                            TEXT_WRITE: begin
                                state <= TEXT_WRITE_EXEC;
                                instruction_busy <= 1'b1;
                            end
                            TEXT_POSITION: begin
                                state <= TEXT_POSITION_EXEC;
                                instruction_busy <= 1'b1;
                            end
                            TEXT_CLEAR: begin
                                state <= TEXT_CLEAR_EXEC;
                                instruction_busy <= 1'b1;
                                clear_row_counter <= 5'h00;
                                clear_col_counter <= 7'h00;
                            end
                            GET_TEXT_AT: begin
                                state <= GET_TEXT_EXEC;
                                instruction_busy <= 1'b1;
                            end
                            default: begin
                                instruction_error <= 1'b1;
                            end
                        endcase
                    end
                end
                
                TEXT_WRITE_EXEC: begin
                    // Write character at current cursor position
                    char_addr_ctrl_internal <= ((cursor_row + scroll_offset) % TOTAL_ROWS) * CHARS_PER_ROW + cursor_col;
                    char_data_out <= {inst_arg0, inst_arg1}; // {attributes, character}
                    char_we <= 1'b1;
                    
                    
                    // Advance cursor
                    if (cursor_col == CHARS_PER_ROW - 1) begin
                        cursor_col <= 7'h00;
                        if (cursor_row == VISIBLE_ROWS - 1) begin
                            // Need to scroll
                            scroll_offset <= (scroll_offset + 1) % TOTAL_ROWS;
                            state <= SCROLL_EXEC; // Clear the new line
                        end else begin
                            cursor_row <= cursor_row + 1;
                            state <= IDLE;
                            instruction_finished <= 1'b1;
                        end
                    end else begin
                        cursor_col <= cursor_col + 1;
                        state <= IDLE;
                        instruction_finished <= 1'b1;
                    end
                end
                
                TEXT_POSITION_EXEC: begin
                    // Move cursor to new position
                    if (inst_arg0 < VISIBLE_ROWS && inst_arg1 < CHARS_PER_ROW) begin
                        cursor_row <= inst_arg0[4:0];
                        cursor_col <= inst_arg1[6:0];
                    end else begin
                        instruction_error <= 1'b1;
                    end
                    state <= IDLE;
                    instruction_finished <= 1'b1;
                end
                
                TEXT_CLEAR_EXEC: begin
                    // Clear all character memory with provided attributes
                    char_addr_ctrl_internal <= clear_row_counter * CHARS_PER_ROW + clear_col_counter;
                    char_data_out <= {inst_arg0, 8'h00}; // {attributes, null char}
                    char_we <= 1'b1;
                    
                    if (clear_col_counter == CHARS_PER_ROW - 1) begin
                        clear_col_counter <= 7'h00;
                        if (clear_row_counter == TOTAL_ROWS - 1) begin
                            // Done clearing
                            state <= IDLE;
                            instruction_finished <= 1'b1;
                        end else begin
                            clear_row_counter <= clear_row_counter + 1;
                        end
                    end else begin
                        clear_col_counter <= clear_col_counter + 1;
                    end
                end
                
                GET_TEXT_EXEC: begin
                    // Set address for character read (cycle 1)
                    if (inst_arg0 < VISIBLE_ROWS && inst_arg1 < CHARS_PER_ROW) begin
                        char_addr_ctrl_internal <= ((inst_arg0 + scroll_offset) % TOTAL_ROWS) * CHARS_PER_ROW + inst_arg1;
                        state <= GET_TEXT_READ; // Wait one cycle for memory read
                    end else begin
                        instruction_error <= 1'b1;
                        state <= IDLE;
                        instruction_finished <= 1'b1;
                    end
                end
                
                GET_TEXT_READ: begin
                    // Read character data (cycle 2) - memory data is now valid
                    result_char_code_reg <= char_data_in[7:0];   // Character code
                    result_char_attr_reg <= char_data_in[15:8];  // Attributes
                    state <= IDLE;
                    instruction_finished <= 1'b1;
                end
                
                SCROLL_EXEC: begin
                    // Clear the new line after scrolling
                    char_addr_ctrl_internal <= ((scroll_offset - 1 + TOTAL_ROWS) % TOTAL_ROWS) * CHARS_PER_ROW + clear_col_counter;
                    char_data_out <= 16'h0000; // Clear character and attributes
                    char_we <= 1'b1;
                    
                    if (clear_col_counter == CHARS_PER_ROW - 1) begin
                        clear_col_counter <= 7'h00;
                        state <= IDLE;
                        instruction_finished <= 1'b1;
                    end else begin
                        clear_col_counter <= clear_col_counter + 1;
                    end
                end
            endcase
        end
    end
    
    //========================================
    // TEXT RENDERER PIPELINE
    //========================================
    
    // Position calculations
    wire [6:0] char_col_disp;       // Character column (0-79)
    wire [4:0] char_row_disp;       // Character row (0-29)
    wire [2:0] pixel_x;             // Pixel within character (0-7)
    wire [3:0] pixel_y;             // Pixel row within character (0-15)
    wire [4:0] actual_row_disp;     // Actual row accounting for scroll
    
    // Assign position calculations
    assign char_col_disp = hcount[9:3];  // hcount / 8
    assign char_row_disp = vcount[8:4];  // vcount / 16  
    assign pixel_x = hcount[2:0];        // hcount % 8
    assign pixel_y = vcount[3:0];        // vcount % 16
    
    // Account for scrolling - wrap around the ring buffer
    assign actual_row_disp = (char_row_disp + scroll_offset >= TOTAL_ROWS) ? 
                            (char_row_disp + scroll_offset - TOTAL_ROWS) : 
                            (char_row_disp + scroll_offset);
    
    // Pipeline registers for display
    reg [6:0] disp_char_col_pipe [0:2];
    reg [4:0] disp_actual_row_pipe [0:2];
    reg [2:0] disp_pixel_x_pipe [0:2];
    reg [3:0] disp_pixel_y_pipe [0:2];
    reg disp_active_pipe [0:2];
    
    // Character data pipeline
    reg [7:0] disp_char_code_pipe [0:1];
    reg [7:0] disp_char_attr_pipe [0:1];
    reg [3:0] disp_fg_color_pipe [0:1];
    reg [2:0] disp_bg_color_pipe [0:1];
    reg disp_blink_pipe [0:1];
    
    // Font data pipeline
    reg [7:0] disp_font_row_pipe;
    reg disp_font_pixel;
    
    // Pixel generation signals
    reg show_pixel;
    
    // Blink counter for blinking text
    reg [24:0] blink_counter;
    wire blink_state;
    
    // Generate blink timing (~1.5Hz blink rate)
    always @(posedge video_clk or negedge reset_n) begin
        if (!reset_n) begin
            blink_counter <= 25'h0;
        end else begin
            blink_counter <= blink_counter + 1;
        end
    end
    assign blink_state = blink_counter[24]; // ~1.5Hz blink
    
    // Pipeline stage 0: Address calculation for display
    always @(posedge video_clk or negedge reset_n) begin
        if (!reset_n) begin
            disp_char_col_pipe[0] <= 7'h00;
            disp_actual_row_pipe[0] <= 5'h00;
            disp_pixel_x_pipe[0] <= 3'h0;
            disp_pixel_y_pipe[0] <= 4'h0;
            disp_active_pipe[0] <= 1'b0;
            disp_char_addr <= 11'h000;
        end else begin
            // Pipeline current position
            disp_char_col_pipe[0] <= char_col_disp;
            disp_actual_row_pipe[0] <= actual_row_disp;
            disp_pixel_x_pipe[0] <= pixel_x;
            disp_pixel_y_pipe[0] <= pixel_y;
            disp_active_pipe[0] <= display_active;
            
            // Calculate character memory address for display
            // Need to look ahead by 2 pixels for pipeline timing
            if (hcount >= 798) begin // Wrap to next line
                disp_char_addr <= ((actual_row_disp + 1) >= TOTAL_ROWS ? 0 : (actual_row_disp + 1)) * CHARS_PER_ROW;
            end else begin
                disp_char_addr <= actual_row_disp * CHARS_PER_ROW + ((hcount + 2) >> 3);
            end
        end
    end
    
    // Pipeline stage 1: Character lookup and decode for display
    always @(posedge video_clk or negedge reset_n) begin
        if (!reset_n) begin
            disp_char_col_pipe[1] <= 7'h00;
            disp_actual_row_pipe[1] <= 5'h00;
            disp_pixel_x_pipe[1] <= 3'h0;
            disp_pixel_y_pipe[1] <= 4'h0;
            disp_active_pipe[1] <= 1'b0;
            disp_char_code_pipe[0] <= 8'h00;
            disp_char_attr_pipe[0] <= 8'h00;
            disp_fg_color_pipe[0] <= 4'h0;
            disp_bg_color_pipe[0] <= 3'h0;
            disp_blink_pipe[0] <= 1'b0;
            font_addr <= 12'h000;
        end else begin
            // Pipeline position
            disp_char_col_pipe[1] <= disp_char_col_pipe[0];
            disp_actual_row_pipe[1] <= disp_actual_row_pipe[0];
            disp_pixel_x_pipe[1] <= disp_pixel_x_pipe[0];
            disp_pixel_y_pipe[1] <= disp_pixel_y_pipe[0];
            disp_active_pipe[1] <= disp_active_pipe[0];
            
            // Decode character data
            disp_char_code_pipe[0] <= char_data_in[7:0];    // Low byte = character
            disp_char_attr_pipe[0] <= char_data_in[15:8];   // High byte = attributes
            disp_fg_color_pipe[0] <= char_data_in[11:8];    // Bits 11-8 = foreground color
            disp_bg_color_pipe[0] <= char_data_in[14:12];   // Bits 14-12 = background color  
            disp_blink_pipe[0] <= char_data_in[15];         // Bit 15 = blink
            
            // Calculate font ROM address
            font_addr <= {char_data_in[7:0], disp_pixel_y_pipe[0]}; // {char_code, row_in_char}
        end
    end
    
    // Pipeline stage 2: Font lookup for display
    always @(posedge video_clk or negedge reset_n) begin
        if (!reset_n) begin
            disp_char_col_pipe[2] <= 7'h00;
            disp_actual_row_pipe[2] <= 5'h00;
            disp_pixel_x_pipe[2] <= 3'h0;
            disp_pixel_y_pipe[2] <= 4'h0;
            disp_active_pipe[2] <= 1'b0;
            disp_char_code_pipe[1] <= 8'h00;
            disp_char_attr_pipe[1] <= 8'h00;
            disp_fg_color_pipe[1] <= 4'h0;
            disp_bg_color_pipe[1] <= 3'h0;
            disp_blink_pipe[1] <= 1'b0;
            disp_font_row_pipe <= 8'h00;
        end else begin
            // Pipeline position and character data
            disp_char_col_pipe[2] <= disp_char_col_pipe[1];
            disp_actual_row_pipe[2] <= disp_actual_row_pipe[1];
            disp_pixel_x_pipe[2] <= disp_pixel_x_pipe[1];
            disp_pixel_y_pipe[2] <= disp_pixel_y_pipe[1];
            disp_active_pipe[2] <= disp_active_pipe[1];
            disp_char_code_pipe[1] <= disp_char_code_pipe[0];
            disp_char_attr_pipe[1] <= disp_char_attr_pipe[0];
            disp_fg_color_pipe[1] <= disp_fg_color_pipe[0];
            disp_bg_color_pipe[1] <= disp_bg_color_pipe[0];
            disp_blink_pipe[1] <= disp_blink_pipe[0];
            
            // Capture font row data
            disp_font_row_pipe <= font_data;
        end
    end
    
    // Pipeline stage 3: Pixel generation and color lookup
    always @(posedge video_clk or negedge reset_n) begin
        if (!reset_n) begin
            disp_font_pixel <= 1'b0;
            palette_addr <= 4'h0;
            pixel_valid <= 1'b0;
            rgb_out <= 6'h00;
            show_pixel <= 1'b0;
        end else begin
            pixel_valid <= disp_active_pipe[2];
            
            if (disp_active_pipe[2]) begin
                // Extract the specific pixel from the font row
                disp_font_pixel <= disp_font_row_pipe[7 - disp_pixel_x_pipe[2]]; // MSB first
                
                // Determine if we should show the pixel (handle blinking)
                show_pixel <= disp_font_pixel && (!disp_blink_pipe[1] || blink_state);
                
                // Select foreground or background color
                if (show_pixel) begin
                    palette_addr <= disp_fg_color_pipe[1];   // Foreground
                end else begin
                    palette_addr <= {1'b0, disp_bg_color_pipe[1]}; // Background (extend to 4 bits)
                end
                
                // Output final RGB (palette lookup happens next clock)
                rgb_out <= palette_data;
            end else begin
                // Outside display area - output black
                rgb_out <= 6'h00;
            end
        end
    end
    
endmodule
