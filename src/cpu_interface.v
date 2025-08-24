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
    output reg [7:0] mode_control       // Register $0000 - video mode selection
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
    localparam WRITE_PIXEL = 8'h10;
    localparam PIXEL_POS = 8'h11;
    localparam WRITE_PIXEL_POS = 8'h12;
    localparam CLEAR_SCREEN = 8'h13;
    localparam GET_PIXEL_AT = 8'h14;
    
    // Valid instruction check
    wire valid_instruction;
    assign valid_instruction = (registers[1] == TEXT_WRITE) || 
                              (registers[1] == TEXT_POSITION) ||
                              (registers[1] == TEXT_CLEAR) ||
                              (registers[1] == GET_TEXT_AT) ||
                              (registers[1] == WRITE_PIXEL) ||
                              (registers[1] == PIXEL_POS) ||
                              (registers[1] == WRITE_PIXEL_POS) ||
                              (registers[1] == CLEAR_SCREEN) ||
                              (registers[1] == GET_PIXEL_AT);
    
    // Execute trigger register addresses
    reg [3:0] execute_addr;
    always @(*) begin
        case (registers[1]) // instruction register $0001
            TEXT_WRITE:      execute_addr = 4'h3; // $0003
            TEXT_POSITION:   execute_addr = 4'h3; // $0003  
            TEXT_CLEAR:      execute_addr = 4'h2; // $0002
            GET_TEXT_AT:     execute_addr = 4'h3; // $0003
            WRITE_PIXEL:     execute_addr = 4'h2; // $0002
            PIXEL_POS:       execute_addr = 4'h5; // $0005
            WRITE_PIXEL_POS: execute_addr = 4'h6; // $0006
            CLEAR_SCREEN:    execute_addr = 4'h2; // $0002
            GET_PIXEL_AT:    execute_addr = 4'h5; // $0005
            default:         execute_addr = 4'hF; // Invalid
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
                // Note: Mode control (register[0]) handled separately in clocked logic
            endcase
        end
    end
    
    // Clocked control logic and state management 
    reg prev_status_read;
    always @(posedge phi2 or negedge reset_n) begin
        if (!reset_n) begin
            // Reset all registers
            for (integer i = 0; i < 16; i = i + 1) begin
                registers[i] <= 8'h00;
            end
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
            
            // Handle mode control register separately (needs clocked behavior)
            if (chip_enable && !rw && addr == 4'h0) begin
                registers[0] <= data_in; // Mode control
                mode_control <= data_in;
            end
            
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

endmodule
