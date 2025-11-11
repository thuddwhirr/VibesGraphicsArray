module text_mode_module (
    input wire video_clk,           // 25.175 MHz pixel clock
    input wire reset_n,             // Active low reset

    // VGA timing inputs
    input wire [9:0] hcount,        // Horizontal pixel counter (0-799)
    input wire [9:0] vcount,        // Vertical line counter (0-524)
    input wire display_active,      // High when in display area

    // Mode control (for cursor enable/blink)
    input wire [7:0] mode_control,  // Mode control register

    // Instruction interface from instruction register
    input wire [7:0] instruction,        // Current instruction opcode
    input wire [7:0] arg_data [0:10],    // Argument registers
    input wire instruction_start,        // Pulse to start instruction
    output reg instruction_busy,         // High when instruction executing
    output reg instruction_finished,     // Pulse when instruction complete
    output reg instruction_error,        // High if error occurred
    
    // Character buffer interface (dual port BRAM)
    output wire [11:0] char_addr,    // Character memory address (unified) - 12-bit for 2560 entries
    input wire [15:0] char_data_in, // Character data read from memory
    output reg [15:0] char_data_out,// Character data to write to memory
    output reg char_we,             // Write enable for character memory
    
    // Font ROM interface
    output reg [11:0] font_addr,    // Font ROM address
    input wire [7:0] font_data,     // 8-bit font row data
    
    // Palette interface - dual port
    output reg [3:0] palette_addr_fg,  // Foreground palette address
    output reg [3:0] palette_addr_bg,  // Background palette address
    input wire [11:0] palette_data_fg,  // Foreground RGB output (12-bit)
    input wire [11:0] palette_data_bg,  // Background RGB output (12-bit)

    // RGB output
    output reg [11:0] rgb_out,      // 12-bit RGB to external DAC
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
    localparam TEXT_COMMAND = 8'h04;
    
    // Text controller state machine states
    localparam IDLE = 4'b0000;
    localparam TEXT_WRITE_EXEC = 4'b0001;
    localparam TEXT_WRITE_COMPLETE = 4'b0010;
    localparam TEXT_POSITION_EXEC = 4'b0011;
    localparam TEXT_CLEAR_EXEC = 4'b0100;
    localparam GET_TEXT_EXEC = 4'b0101;
    localparam GET_TEXT_READ = 4'b0110;  // New state for memory read timing
    localparam SCROLL_EXEC = 4'b0111;
    localparam TEXT_COMMAND_EXEC = 4'b1000;
    
    reg [3:0] state;
    
    // Text controller registers
    reg [6:0] cursor_col;           // Cursor column (0-79)
    reg [4:0] cursor_row;           // Cursor row (0-29)
    reg [4:0] scroll_offset;        // Current scroll position (0-30)
    reg [4:0] clear_row_counter;    // Counter for clearing operations
    reg [6:0] clear_col_counter;    // Counter for clearing operations
    reg [7:0] default_attributes;   // Default character attributes for 0x00 and scrolling
    
    // Instruction arguments (latched on instruction_start)
    reg [7:0] inst_arg0, inst_arg1, inst_arg2;
    
    // Result registers
    reg [7:0] result_char_code_reg;
    reg [7:0] result_char_attr_reg;
    
    // Connect result outputs
    assign result_char_code = result_char_code_reg;
    assign result_char_attr = result_char_attr_reg;
    
    // Address management - separate controller and display addresses
    reg [11:0] char_addr_ctrl_internal;  // Internal controller address (12-bit)
    reg [11:0] disp_char_addr;          // Display address (12-bit)
    
    // Multiplex address based on whether we're writing OR doing GetTextAt read
    wire controller_needs_addr = char_we || (state == GET_TEXT_EXEC) || (state == GET_TEXT_READ);
    assign char_addr = controller_needs_addr ? char_addr_ctrl_internal : disp_char_addr;
    
    //========================================
    // TEXT CONTROLLER STATE MACHINE
    //========================================
    
    // Synchronize instruction_start to video_clk domain
    reg instruction_start_sync1, instruction_start_sync2, instruction_start_prev;
    wire instruction_start_edge;
    
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
            char_addr_ctrl_internal <= 12'h000;
            default_attributes <= 8'h01; // White on black by default (fg=1, bg=0)
        end else begin
            // Default values
            instruction_finished <= 1'b0;
            instruction_error <= 1'b0;
            char_we <= 1'b0;
            
            case (state)
                IDLE: begin
                    instruction_busy <= 1'b0;
                    if (instruction_start_edge) begin
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
                                default_attributes <= arg_data[0]; // Use arg_data directly, not inst_arg0
                            end
                            GET_TEXT_AT: begin
                                state <= GET_TEXT_EXEC;
                                instruction_busy <= 1'b1;
                            end
                            TEXT_COMMAND: begin
                                state <= TEXT_COMMAND_EXEC;
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
                    char_addr_ctrl_internal <= ((cursor_row + scroll_offset) % TOTAL_ROWS) * 7'd80 + cursor_col;
                    // Use default attributes if arg0 is 0x00, otherwise use provided attributes
                    char_data_out <= {(inst_arg0 == 8'h00) ? default_attributes : inst_arg0, inst_arg1}; // {attributes, character}
                    char_we <= 1'b1;
                    
                    // Advance cursor and move to completion state
                    if (cursor_col == CHARS_PER_ROW - 1) begin
                        cursor_col <= 7'h00;
                        if (cursor_row == VISIBLE_ROWS - 1) begin
                            // Need to scroll
                            scroll_offset <= (scroll_offset + 1) % TOTAL_ROWS;
                            state <= SCROLL_EXEC; // Clear the new line
                        end else begin
                            cursor_row <= cursor_row + 1;
                            state <= TEXT_WRITE_COMPLETE;
                        end
                    end else begin
                        cursor_col <= cursor_col + 1;
                        state <= TEXT_WRITE_COMPLETE;
                    end
                end
                
                TEXT_WRITE_COMPLETE: begin
                    // Complete the write operation
                    char_we <= 1'b0;
                    state <= IDLE;
                    instruction_finished <= 1'b1;
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
                    char_addr_ctrl_internal <= clear_row_counter * 7'd80 + clear_col_counter;
                    char_data_out <= {inst_arg0, 8'h00}; // {attributes, null char}
                    char_we <= 1'b1;
                    
                    if (clear_col_counter == CHARS_PER_ROW - 1) begin
                        clear_col_counter <= 7'h00;
                        if (clear_row_counter == TOTAL_ROWS - 1) begin
                            // Done clearing - reset cursor and scroll position
                            cursor_col <= 7'h00;
                            cursor_row <= 5'h00;
                            scroll_offset <= 5'h00;
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
                        char_addr_ctrl_internal <= ((inst_arg0 + scroll_offset) % TOTAL_ROWS) * 7'd80 + inst_arg1;
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
                    // Clear the new line after scrolling using default attributes
                    char_addr_ctrl_internal <= ((scroll_offset - 1 + TOTAL_ROWS) % TOTAL_ROWS) * 7'd80 + clear_col_counter;
                    char_data_out <= {default_attributes, 8'h00}; // Clear character with default background
                    char_we <= 1'b1;
                    
                    if (clear_col_counter == CHARS_PER_ROW - 1) begin
                        clear_col_counter <= 7'h00;
                        state <= IDLE;
                        instruction_finished <= 1'b1;
                    end else begin
                        clear_col_counter <= clear_col_counter + 1;
                    end
                end
                
                TEXT_COMMAND_EXEC: begin
                    case (inst_arg0)
                        8'h08: begin // Backspace - move back one character and write space
                            if (cursor_col > 0) begin
                                cursor_col <= cursor_col - 1;
                                char_addr_ctrl_internal <= ((cursor_row + scroll_offset) % TOTAL_ROWS) * 7'd80 + (cursor_col - 1);
                                char_data_out <= {default_attributes, 8'h20}; // Write space character
                                char_we <= 1'b1;
                            end
                            state <= IDLE;
                            instruction_finished <= 1'b1;
                        end
                        8'h09: begin // Tab - advance cursor 8 increments
                            if (cursor_col < CHARS_PER_ROW - 8) begin
                                cursor_col <= (cursor_col + 8) & 7'h78; // Round to next 8-column boundary
                            end else begin
                                cursor_col <= CHARS_PER_ROW - 1; // Move to end of line if tab would exceed
                            end
                            state <= IDLE;
                            instruction_finished <= 1'b1;
                        end
                        8'h0A: begin // Line feed - move cursor to col 0 of next row
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
                        end
                        8'h0D: begin // Carriage return - move cursor to col 0 of current row
                            cursor_col <= 7'h00;
                            state <= IDLE;
                            instruction_finished <= 1'b1;
                        end
                        8'h7F: begin // Delete - set char at current cursor position to space
                            char_addr_ctrl_internal <= ((cursor_row + scroll_offset) % TOTAL_ROWS) * 7'd80 + cursor_col;
                            char_data_out <= {default_attributes, 8'h20}; // Write space character
                            char_we <= 1'b1;
                            state <= IDLE;
                            instruction_finished <= 1'b1;
                        end
                        default: begin
                            instruction_error <= 1'b1;
                            state <= IDLE;
                            instruction_finished <= 1'b1;
                        end
                    endcase
                end
            endcase
        end
    end
    

    //========================================
    // Non-pipeline Text Renderer
    //========================================


    wire [7:0]column_pos;          //the character column currently being rendered (hcount / 80)
    wire [7:0]row_pos;             //the character row currently being rendered (vcount / 30)
    wire [7:0]pixel_x;              //the relative x coordinate of the character being rendered (hcount % 8)
    wire [7:0]pixel_y;              //the relavite y coordinate of the character being rendered (vcount % 16)


    wire [7:0] attributes_data;          //attributes half of the character data
    wire [3:0] foreground_index;          //foreground portion of current returned attribute
    wire [3:0] background_index;          //background portion of current returned attribute
    wire blink_bit;                      //blink flag from attributes
    wire [7:0] character_code;      //character code returned from currrent returned charecter
    wire [7:0] font_row;            //font row for the character_code and the current pixel_y; 

    wire [11:0] foreground_rgb;     //rgb data returned for the foreground index (12-bit)
    wire [11:0] background_rgb;     //rgb data returned for the background index (12-bit)
    
    // Blink support
    reg [24:0] blink_counter;       // Character attribute blink counter
    wire blink_state;

    // Hardware cursor support
    reg [3:0] cursor_blink_counter; // Cursor blink counter (VSYNC÷16)
    wire cursor_blink_state;
    wire cursor_enable;
    wire cursor_blink_enable;
    wire at_cursor_position;

    assign column_pos = (hcount < 640) ? (hcount + 2) / 8 : 10'd0;
    assign row_pos = (vcount < 480) ? vcount / 16 : 10'd0;
    assign pixel_x = hcount % 4'd8;
    assign pixel_y = (hcount < 640) ? vcount % 5'd16 : (vcount + 1) % 5'd16;

    // Hardware cursor control
    assign cursor_enable = mode_control[5];       // Bit 5: Cursor enable
    assign cursor_blink_enable = mode_control[6]; // Bit 6: Cursor blink
    assign at_cursor_position = (row_pos == cursor_row) && (column_pos == cursor_col);
    assign cursor_blink_state = cursor_blink_counter[3]; // VSYNC÷16 = bit 3

    //calculate address to pass to character memory. Use the shifted column, which will change 2 clock cycles before the actual column. 
    assign disp_char_addr = (((scroll_offset + row_pos) % TOTAL_ROWS) * 8'd80) + column_pos;

    //read the output of character memory based on last cycle's address. 
    assign attributes_data = char_data_in[15:8];
    assign character_code = char_data_in[7:0];
    assign foreground_index = attributes_data[3:0]; 
    assign background_index = attributes_data[6:4];  // bits 6-4 for background (3 bits)
    assign blink_bit = attributes_data[7];           // bit 7 for blink

    //set the font address to the character code * 16 rows + the current pixel_y.
    //this is based on the char code requested last cycle, which is based on the char requested 2 cycles ago
    assign font_addr = (character_code * 8'd16) + pixel_y;

    //read the output of font rom
    assign font_row = font_data;

    //set foreground and background rgb from parallel palette lookups
    assign foreground_rgb = palette_data_fg;
    assign background_rgb = palette_data_bg;

    //set both palette addresses for parallel lookup
    assign palette_addr_fg = foreground_index;
    assign palette_addr_bg = background_index;

    // Generate blink timing (~1.5Hz blink rate for character attributes)
    always @(posedge video_clk or negedge reset_n) begin
        if (!reset_n) begin
            blink_counter <= 25'h0;
        end else begin
            blink_counter <= blink_counter + 1;
        end
    end
    assign blink_state = blink_counter[24]; // ~1.5Hz blink (VSYNC÷32)

    // Generate cursor blink timing (~3.75Hz = VSYNC÷16)
    // Increment cursor counter on VSYNC (detect start of new frame)
    reg prev_vcount_zero;
    wire vsync_pulse;
    assign vsync_pulse = (vcount == 10'd0) && !prev_vcount_zero;

    always @(posedge video_clk or negedge reset_n) begin
        if (!reset_n) begin
            cursor_blink_counter <= 4'h0;
            prev_vcount_zero <= 1'b0;
        end else begin
            prev_vcount_zero <= (vcount == 10'd0);
            if (vsync_pulse) begin
                cursor_blink_counter <= cursor_blink_counter + 1;
            end
        end
    end
    
    // Pixel visibility with blink support
    wire show_pixel = font_row[7-pixel_x] && (!blink_bit || blink_state);

    // Hardware cursor visibility logic
    wire cursor_visible;
    assign cursor_visible = cursor_enable &&                    // Cursor enabled
                           at_cursor_position &&               // At cursor position
                           (!cursor_blink_enable || cursor_blink_state); // Solid or blink ON

    //Register rgb_out to prevent timing glitches that cause color bleeding
    always @(posedge video_clk) begin
        pixel_valid <= display_active;

        // Register rgb_out for stable VGA timing
        if (display_active) begin
            // Show cursor as solid block using foreground color when cursor is visible
            if (cursor_visible) begin
                rgb_out <= foreground_rgb;  // Cursor block uses character's foreground color
            end else begin
                rgb_out <= show_pixel ? foreground_rgb : background_rgb;  // Normal rendering
            end
        end else begin
            rgb_out <= 12'd0;  // Changed from 6'd0 to 12'd0 for 12-bit RGB
        end
    end

endmodule
