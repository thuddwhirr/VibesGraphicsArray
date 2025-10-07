module cpu_interface (
    // CPU Bus Interface (1 MHz domain)
    input wire phi2,           // CPU clock 1MHz
    input wire reset_n,        // Active low reset
    input wire [3:0] addr,     // 4-bit address bus
    input wire [7:0] data_in,  // 8-bit data from CPU
    output reg [7:0] data_out, // 8-bit data to CPU
    input wire rw,             // Read/Write signal (1=read, 0=write)
    input wire ce0,            // Chip enable 0
    input wire ce1b,           // Chip enable 1 (active low)
    
    // Instruction Execution Interface
    output reg [7:0] instruction,        // Current instruction opcode
    output reg [7:0] arg_data [0:10],    // Argument registers $0002-$000C
    output reg instruction_start,        // Pulse to start instruction
    input wire instruction_busy,         // High when instruction executing
    input wire instruction_finished,     // Pulse when instruction complete
    input wire instruction_error,        // High if error occurred
    
    // Result Interface
    input wire [7:0] result_0,          // Output register $000D
    input wire [7:0] result_1,          // Output register $000E
    
    // Mode Control
    output reg [7:0] mode_control,      // Register $0000 - video mode selection

    // Writable Palette Interface
    output wire [7:0] palette_write_addr,    // Palette write address
    output wire [11:0] palette_write_data,   // Palette write data (12-bit RGB)
    output wire palette_write_enable,        // Palette write enable pulse
    input wire [11:0] palette_read_data,     // Palette read data (for GET_PALETTE_ENTRY)
    output wire [7:0] palette_result_low,    // GET_PALETTE_ENTRY result low byte
    output wire [7:0] palette_result_high    // GET_PALETTE_ENTRY result high byte
);

    // Internal registers
    reg chip_enable;
    reg [7:0] registers [0:15];         // 16 8-bit registers $0000-$000F
    reg [7:0] status_reg;               // Status register $000F
    reg instruction_pending;            // Flag for pending instruction
    reg prev_instruction_busy;          // Previous state for edge detection
    
    // Chip enable logic
    always @(*) begin
        chip_enable = ce0 & ~ce1b;
    end
    
    // Status register bits
    localparam STATUS_BUSY = 0;         // Bit 0: Instruction busy
    localparam STATUS_ERROR = 1;        // Bit 1: Instruction error
    localparam STATUS_READY = 7;        // Bit 7: Ready for new instruction
    
    // Instruction opcodes
    localparam TEXT_WRITE = 8'h00;
    localparam TEXT_POSITION = 8'h01;
    localparam TEXT_CLEAR = 8'h02;
    localparam GET_TEXT_AT = 8'h03;
    localparam TEXT_COMMAND = 8'h04;
    localparam WRITE_PIXEL = 8'h10;
    localparam PIXEL_POS = 8'h11;
    localparam WRITE_PIXEL_POS = 8'h12;
    localparam CLEAR_SCREEN = 8'h13;
    localparam GET_PIXEL_AT = 8'h14;
    localparam SET_PALETTE_ENTRY = 8'h20;
    localparam GET_PALETTE_ENTRY = 8'h21;
    
    // Valid instruction check
    wire valid_instruction;
    assign valid_instruction = (registers[1] == TEXT_WRITE) ||
                              (registers[1] == TEXT_POSITION) ||
                              (registers[1] == TEXT_CLEAR) ||
                              (registers[1] == GET_TEXT_AT) ||
                              (registers[1] == TEXT_COMMAND) ||
                              (registers[1] == WRITE_PIXEL) ||
                              (registers[1] == PIXEL_POS) ||
                              (registers[1] == WRITE_PIXEL_POS) ||
                              (registers[1] == CLEAR_SCREEN) ||
                              (registers[1] == GET_PIXEL_AT) ||
                              (registers[1] == SET_PALETTE_ENTRY) ||
                              (registers[1] == GET_PALETTE_ENTRY);
    
    // Execute trigger register addresses
    reg [3:0] execute_addr;
    always @(*) begin
        case (registers[1]) // instruction register $0001
            TEXT_WRITE:        execute_addr = 4'h3; // $0003 - execute on character write
            TEXT_POSITION:     execute_addr = 4'h3; // $0003
            TEXT_CLEAR:        execute_addr = 4'h2; // $0002
            GET_TEXT_AT:       execute_addr = 4'h3; // $0003
            TEXT_COMMAND:      execute_addr = 4'h2; // $0002
            WRITE_PIXEL:       execute_addr = 4'h2; // $0002
            PIXEL_POS:         execute_addr = 4'h5; // $0005
            WRITE_PIXEL_POS:   execute_addr = 4'h6; // $0006
            CLEAR_SCREEN:      execute_addr = 4'h2; // $0002
            GET_PIXEL_AT:      execute_addr = 4'h5; // $0005
            SET_PALETTE_ENTRY: execute_addr = 4'h4; // $0004 - RGB high byte
            GET_PALETTE_ENTRY: execute_addr = 4'h2; // $0002 - palette index
            default:           execute_addr = 4'hF; // Invalid
        endcase
    end
    
    // CPU Bus Interface - Reads (clocked output to CPU)
    always @(posedge phi2 or negedge reset_n) begin
        if (!reset_n) begin
            data_out <= 8'h00;
        end else if (chip_enable && rw) begin // CPU Read
            case (addr)
                4'h0: data_out <= registers[0];  // Mode control
                4'h1: data_out <= registers[1];  // Instruction
                4'h2: data_out <= registers[2];  // Arg 0
                4'h3: data_out <= registers[3];  // Arg 1
                4'h4: data_out <= registers[4];  // Arg 2
                4'h5: data_out <= registers[5];  // Arg 3
                4'h6: data_out <= registers[6];  // Arg 4
                4'h7: data_out <= registers[7];  // Arg 5
                4'h8: data_out <= registers[8];  // Arg 6
                4'h9: data_out <= registers[9];  // Arg 7
                4'hA: data_out <= registers[10]; // Arg 8
                4'hB: data_out <= registers[11]; // Arg 9
                4'hC: data_out <= registers[12]; // Arg 10
                4'hD: data_out <= result_0;      // Result 0 (read-only)
                4'hE: data_out <= result_1;      // Result 1 (read-only)
                4'hF: data_out <= status_reg;    // Status (read-only)
                default: data_out <= 8'h00;
            endcase
        end else begin
            data_out <= 8'hZZ; // High impedance when not reading
        end
    end
    
    // Combinational register writes (level-sensitive for reliable 65C02 timing)
    always @(*) begin
        if (phi2 && chip_enable && !rw && reset_n) begin
            case (addr)
                4'h0: registers[0] = data_in;  // Mode control
                4'h1: registers[1] = data_in;  // Instruction
                4'h2: registers[2] = data_in;  // Arg 0
                4'h3: registers[3] = data_in;  // Arg 1  
                4'h4: registers[4] = data_in;  // Arg 2
                4'h5: registers[5] = data_in;  // Arg 3
                4'h6: registers[6] = data_in;  // Arg 4
                4'h7: registers[7] = data_in;  // Arg 5
                4'h8: registers[8] = data_in;  // Arg 6
                4'h9: registers[9] = data_in;  // Arg 7
                4'hA: registers[10] = data_in; // Arg 8
                4'hB: registers[11] = data_in; // Arg 9
                4'hC: registers[12] = data_in; // Arg 10
                // Note: $000D, $000E, $000F are read-only
            endcase
        end
    end
    
    // Clocked control logic and state management 
    reg prev_status_read;
    always @(posedge phi2 or negedge reset_n) begin
        if (!reset_n) begin
            // Reset only registers not driven by combinational logic
            // registers[0] through [12] are driven by combinational logic above
            registers[13] <= 8'h00;  // Reserved
            registers[14] <= 8'h00;  // Reserved  
            registers[15] <= 8'h00;  // Reserved
            status_reg <= 8'h80; // Ready bit set on reset
            prev_status_read <= 1'b0;
            mode_control <= 8'h00;
            instruction_pending <= 1'b0;
            instruction <= 8'h00;
            instruction_start <= 1'b0;
            prev_instruction_busy <= 1'b0;
        end else begin
            prev_status_read <= (chip_enable && rw && addr == 4'hF);
            prev_instruction_busy <= instruction_busy;
            instruction_start <= 1'b0; // Default to no start pulse
            
            // Update mode_control from register[0] (driven by combinational logic)
            mode_control <= registers[0];
            
            // Check if this write should trigger instruction execution
            if (chip_enable && !rw && addr == execute_addr && valid_instruction) begin
                if (!status_reg[STATUS_BUSY]) begin
                    instruction_pending <= 1'b1;
                end else begin
                    // Set error bit if trying to execute while busy
                    status_reg[STATUS_ERROR] <= 1'b1;
                end
            end
            
            // Start new instruction if pending and not busy
            if (instruction_pending && !instruction_busy) begin
                instruction <= registers[1];
                // Copy argument registers
                arg_data[0] <= registers[2];   // 8 bits
                arg_data[1] <= registers[3];
                arg_data[2] <= registers[4];
                arg_data[3] <= registers[5];
                arg_data[4] <= registers[6];
                arg_data[5] <= registers[7];
                arg_data[6] <= registers[8];
                arg_data[7] <= registers[9];
                arg_data[8] <= registers[10];
                arg_data[9] <= registers[11];
                arg_data[10] <= registers[12];
                
                instruction_start <= 1'b1; // Pulse to start
                instruction_pending <= 1'b0;
            end
            
            // Update busy bit
            status_reg[STATUS_BUSY] <= instruction_busy;
            
            // Update ready bit (inverse of busy)
            status_reg[STATUS_READY] <= ~instruction_busy;
            
            // Clear error bit on status register read (edge detection)
            if ((chip_enable && rw && addr == 4'hF) && !prev_status_read) begin
                status_reg[STATUS_ERROR] <= 1'b0;
            end
            
            // Set error bit if instruction_error is asserted
            if (instruction_error) begin
                status_reg[STATUS_ERROR] <= 1'b1;
            end
            
            // Clear error on instruction completion
            if (instruction_finished) begin
                status_reg[STATUS_ERROR] <= 1'b0;
            end
        end
    end

    //========================================
    // PALETTE INSTRUCTION HANDLING
    //========================================

    // Palette instructions are handled directly (not routed to text/graphics modules)
    wire palette_instruction_active;
    assign palette_instruction_active = (instruction == SET_PALETTE_ENTRY) ||
                                       (instruction == GET_PALETTE_ENTRY);

    // SET_PALETTE_ENTRY: Write palette entry
    // $0002: Palette index (0-255)
    // $0003: RGB low byte (GGGG BBBB)
    // $0004: RGB high byte (xxxx RRRR) - execute on write
    assign palette_write_addr = arg_data[0];  // $0002
    assign palette_write_data = {arg_data[2][3:0], arg_data[1][7:4], arg_data[1][3:0]};  // {RRRR, GGGG, BBBB}

    // Generate write pulse on execute trigger for SET_PALETTE_ENTRY
    reg palette_write_trigger;
    always @(posedge phi2 or negedge reset_n) begin
        if (!reset_n) begin
            palette_write_trigger <= 1'b0;
        end else begin
            // Pulse when writing to execute register for SET_PALETTE_ENTRY
            if (chip_enable && !rw && (addr == execute_addr) &&
                (registers[1] == SET_PALETTE_ENTRY)) begin
                palette_write_trigger <= 1'b1;
            end else begin
                palette_write_trigger <= 1'b0;
            end
        end
    end
    assign palette_write_enable = palette_write_trigger;

    // GET_PALETTE_ENTRY: Read palette entry and store results
    // $0002: Palette index (0-255) - execute on write
    // Result returned in $000D (RGB low byte: GGGG BBBB), $000E (RGB high byte: RRRR xxxx)
    reg [7:0] palette_result_low_reg, palette_result_high_reg;

    always @(posedge phi2 or negedge reset_n) begin
        if (!reset_n) begin
            palette_result_low_reg <= 8'h00;
            palette_result_high_reg <= 8'h00;
        end else begin
            // Latch palette read data when executing GET_PALETTE_ENTRY
            if (chip_enable && !rw && (addr == execute_addr) &&
                (registers[1] == GET_PALETTE_ENTRY)) begin
                palette_result_low_reg <= palette_read_data[7:0];   // GGGG BBBB
                palette_result_high_reg <= {palette_read_data[11:8], 4'h0};  // RRRR 0000
            end
        end
    end

    assign palette_result_low = palette_result_low_reg;
    assign palette_result_high = palette_result_high_reg;

endmodule
