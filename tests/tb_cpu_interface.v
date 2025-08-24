// Testbench for CPU interface module
`include "test_common.vh"

module tb_cpu_interface;

    // Inputs
    reg phi2;
    reg reset_n;
    reg [3:0] addr;
    reg [7:0] data_in;
    reg rw;
    reg ce0;
    reg ce1b;
    
    // Outputs
    wire [7:0] data_out;
    wire [7:0] instruction;
    wire [7:0] arg_data [0:10];
    wire instruction_start;
    wire [7:0] mode_control;
    
    // Bidirectional data bus
    wire [7:0] data_bus;
    reg [7:0] cpu_data_out;
    reg cpu_driving_bus;
    
    // Bus control
    assign data_bus = cpu_driving_bus ? cpu_data_out : 8'hZZ;
    
    // Mock instruction execution signals
    reg instruction_busy;
    reg instruction_finished;
    reg instruction_error;
    reg [7:0] result_0, result_1;
    
    // Instantiate the Unit Under Test (UUT)
    cpu_interface uut (
        .phi2(phi2),
        .reset_n(reset_n),
        .addr(addr),
        .data_in(data_bus),
        .data_out(data_out),
        .rw(rw),
        .ce0(ce0),
        .ce1b(ce1b),
        .instruction(instruction),
        .arg_data(arg_data),
        .instruction_start(instruction_start),
        .instruction_busy(instruction_busy),
        .instruction_finished(instruction_finished),
        .instruction_error(instruction_error),
        .result_0(result_0),
        .result_1(result_1),
        .mode_control(mode_control)
    );
    
    // Clock generation - 1 MHz PHI2
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
            #100; // Hold time
            
            @(negedge phi2);
            cpu_driving_bus = 1'b0;
            rw = 1'b1;
            ce0 = 1'b0;
            ce1b = 1'b1;
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
            #200; // Access time
            read_data = data_out;
            
            @(negedge phi2);
            ce0 = 1'b0;
            ce1b = 1'b1;
        end
    endtask
    
    // Test sequence
    reg [7:0] read_value;
    initial begin
        // Initialize VCD dump
        $dumpfile("cpu_interface.vcd");
        $dumpvars(0, tb_cpu_interface);
        
        $display("Starting CPU Interface Test");
        
        // Initialize inputs
        reset_n = 0;
        addr = 4'h0;
        rw = 1'b1;
        ce0 = 1'b0;
        ce1b = 1'b1;
        cpu_driving_bus = 1'b0;
        instruction_busy = 1'b0;
        instruction_finished = 1'b0;
        instruction_error = 1'b0;
        result_0 = 8'h00;
        result_1 = 8'h00;
        
        // Wait for reset
        `WAIT_CYCLES(phi2, 5);
        reset_n = 1;
        $display("Reset released at %t", $time);
        
        `WAIT_CYCLES(phi2, 2);
        
        // Test 1: Basic register read/write
        $display("Test 1: Basic register read/write");
        
        // Write to mode control register
        cpu_write(4'h0, 8'hA5);
        cpu_read(4'h0, read_value);
        `ASSERT(read_value == 8'hA5, "Mode control register read/write failed");
        `ASSERT(mode_control == 8'hA5, "Mode control output not updated");
        
        // Write to instruction register
        cpu_write(4'h1, 8'h42);
        cpu_read(4'h1, read_value);
        `ASSERT(read_value == 8'h42, "Instruction register read/write failed");
        
        // Write to argument registers
        for (integer i = 2; i <= 12; i = i + 1) begin
            cpu_write(i[3:0], 8'h10 + i);
            cpu_read(i[3:0], read_value);
            `ASSERT(read_value == (8'h10 + i), "Argument register read/write failed");
        end
        
        // Test 2: Read-only registers
        $display("Test 2: Read-only registers");
        
        result_0 = 8'hDE;
        result_1 = 8'hAD;
        
        cpu_read(4'hD, read_value);
        `ASSERT(read_value == 8'hDE, "Result 0 register read failed");
        
        cpu_read(4'hE, read_value);
        `ASSERT(read_value == 8'hAD, "Result 1 register read failed");
        
        // Test 3: Status register
        $display("Test 3: Status register functionality");
        
        cpu_read(4'hF, read_value);
        `ASSERT(read_value[7] == 1'b1, "Ready bit should be set initially");
        `ASSERT(read_value[0] == 1'b0, "Busy bit should be clear initially");
        
        // Test 4: Instruction execution triggering
        $display("Test 4: Instruction execution");
        
        // Set up TextWrite instruction (0x00)
        cpu_write(4'h1, 8'h00);  // TextWrite opcode
        cpu_write(4'h2, 8'h07);  // Attributes
        
        // Monitor instruction_start signal (simplified)
        // Just check after triggering execution
        
        // Trigger execution by writing to execute register (0x03 for TextWrite)
        cpu_write(4'h3, 8'h41);  // Character 'A'
        
        `WAIT_CYCLES(phi2, 2);
        
        // Simulate instruction execution
        instruction_busy = 1'b1;
        `WAIT_CYCLES(phi2, 5);
        
        // Check status register shows busy
        cpu_read(4'hF, read_value);
        `ASSERT(read_value[0] == 1'b1, "Busy bit should be set during execution");
        `ASSERT(read_value[7] == 1'b0, "Ready bit should be clear during execution");
        
        // Complete instruction
        instruction_finished = 1'b1;
        `WAIT_CYCLES(phi2, 1);
        instruction_finished = 1'b0;
        instruction_busy = 1'b0;
        
        `WAIT_CYCLES(phi2, 2);
        
        // Check status register shows ready
        cpu_read(4'hF, read_value);
        `ASSERT(read_value[0] == 1'b0, "Busy bit should be clear after execution");
        `ASSERT(read_value[7] == 1'b1, "Ready bit should be set after execution");
        
        // Test 5: Error handling
        $display("Test 5: Error handling");
        
        // Try to execute while busy
        instruction_busy = 1'b1;
        cpu_write(4'h3, 8'h42);  // Try to trigger another execution
        
        `WAIT_CYCLES(phi2, 2);
        
        cpu_read(4'hF, read_value);
        `ASSERT(read_value[1] == 1'b1, "Error bit should be set when executing while busy");
        
        // Clear error by reading status
        cpu_read(4'hF, read_value);
        `WAIT_CYCLES(phi2, 1);
        cpu_read(4'hF, read_value);
        `ASSERT(read_value[1] == 1'b0, "Error bit should clear after status read");
        
        instruction_busy = 1'b0;
        
        // Test 6: Instruction error propagation
        $display("Test 6: Instruction error propagation");
        
        cpu_write(4'h3, 8'h43);  // Trigger execution
        `WAIT_CYCLES(phi2, 2);
        
        instruction_error = 1'b1;
        `WAIT_CYCLES(phi2, 1);
        instruction_error = 1'b0;
        
        cpu_read(4'hF, read_value);
        `ASSERT(read_value[1] == 1'b1, "Error bit should be set when instruction_error asserted");
        
        // Test 7: Chip enable logic
        $display("Test 7: Chip enable logic");
        
        // Test with ce0=0
        @(negedge phi2);
        addr = 4'h0;
        rw = 1'b1;
        ce0 = 1'b0;  // Disabled
        ce1b = 1'b0;
        
        @(posedge phi2);
        #200;
        `ASSERT(data_out === 8'hZZ, "Data bus should be high-Z when not enabled");
        
        // Test with ce1b=1
        @(negedge phi2);
        ce0 = 1'b1;
        ce1b = 1'b1;  // Disabled
        
        @(posedge phi2);
        #200;
        `ASSERT(data_out === 8'hZZ, "Data bus should be high-Z when not enabled");
        
        $display("All CPU interface tests passed!");
        $finish;
    end
    
    // Timeout protection
    initial begin
        #100000000; // 100ms timeout
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule