//========================================
// CHARACTER BUFFER - 2560 x 16-bit
// Text mode ring buffer storage
//========================================
module character_buffer (
    input wire clka,            // Port A clock (video domain - 25.175MHz)
    input wire clkb,            // Port B clock (video domain - 25.175MHz) 
    input wire reset_n,         // Active low reset
    
    // Port A: Read/Write for text controller state machine
    input wire [11:0] addra,    // Address A (0-2559) - needs 12 bits
    input wire [15:0] dina,     // Data input A
    output reg [15:0] douta,    // Data output A
    input wire wea,             // Write enable A
    
    // Port B: Read-only for text renderer pipeline
    input wire [11:0] addrb,    // Address B (0-2559) - needs 12 bits
    output reg [15:0] doutb     // Data output B
);

    // Character buffer memory array
    reg [15:0] char_mem [0:2559];
    
    // Initialize memory to spaces with default attributes
    integer i;
    initial begin
        for (i = 0; i < 2560; i = i + 1) begin
            char_mem[i] = 16'h0720; // {attr=0x07 (white on black), char=0x20 (space)}
        end
    end
    
    // Port A: Read/Write operations
    always @(posedge clka) begin
        if (wea) begin
            char_mem[addra] <= dina;
        end
        douta <= char_mem[addra];
    end
    
    // Port B: Read-only operations
    always @(posedge clkb) begin
        doutb <= char_mem[addrb];
    end

endmodule

//========================================
// VIDEO MEMORY - 76800 x 8-bit
// Graphics mode frame buffer
//========================================
module video_memory (
    input wire clka,            // Port A clock (video domain - 25.175MHz)
    input wire clkb,            // Port B clock (video domain - 25.175MHz)
    input wire reset_n,         // Active low reset
    
    // Port A: Read/Write for graphics controller state machine
    input wire [16:0] addra,    // Address A (0-76799)
    input wire [7:0] dina,      // Data input A
    output reg [7:0] douta,     // Data output A
    input wire wea,             // Write enable A
    
    // Port B: Read-only for graphics renderer pipeline
    input wire [16:0] addrb,    // Address B (0-76799)
    output reg [7:0] doutb      // Data output B
);

    // Simple single-port memory - more reliable for synthesis
    reg [7:0] video_mem [0:76799];
    
    initial begin
        for (integer i = 0; i < 76800; i = i + 1) begin
            video_mem[i] = 8'h00;
        end
    end

    // Single port with priority: writes on port A, reads on port B
    always @(posedge clka) begin
        if (wea) begin
            video_mem[addra] <= dina;
            douta <= dina;  // Write-through
        end else begin
            douta <= video_mem[addra];
        end
        
        // Port B always reads (display has priority when not writing)
        doutb <= video_mem[addrb];
    end

endmodule

//========================================
// FONT ROM - 4096 x 8-bit (256 chars x 16 rows)
// 8x16 pixel character font
//========================================
module font_rom (
    input wire clk,             // Clock
    input wire [11:0] addr,     // Address: {char_code[7:0], row[3:0]}
    output reg [7:0] data       // 8-bit font row data
);

    // Font memory array
    reg [7:0] font_mem [0:4095];
    
    // Load font data from memory file
    initial begin
        $readmemb("font_8x16.mem", font_mem);
    end
    
    // Synchronous read
    always @(posedge clk) begin
        data <= font_mem[addr];
    end

endmodule

//========================================
// COLOR PALETTE - 16 x 6-bit RGB
// 16 color palette for indexed color modes
//========================================
module color_palette (
    input wire clk,             // Clock
    input wire reset_n,         // Active low reset
    
    // Dual read interface
    input wire [3:0] read_addr_a, // Read address A (0-15) - foreground
    output reg [5:0] read_data_a, // 6-bit RGB output A
    input wire [3:0] read_addr_b, // Read address B (0-15) - background
    output reg [5:0] read_data_b, // 6-bit RGB output B
    
    // Write interface (for palette updates)
    input wire [3:0] write_addr,// Write address (0-15)
    input wire [5:0] write_data,// 6-bit RGB input
    input wire write_enable     // Write enable
);

    // Palette memory array
    reg [5:0] palette_mem [0:15];
    
    // Initialize with default 16-color palette
    initial begin
        palette_mem[0]  = 6'b000000; // Black
        palette_mem[1]  = 6'b111111; // White
        palette_mem[2]  = 6'b001100; // Bright Green
        palette_mem[3]  = 6'b000100; // Dark Green
        palette_mem[4]  = 6'b110000; // Red
        palette_mem[5]  = 6'b000011; // Blue
        palette_mem[6]  = 6'b111100; // Yellow
        palette_mem[7]  = 6'b110011; // Magenta
        palette_mem[8]  = 6'b001111; // Cyan
        palette_mem[9]  = 6'b100000; // Dark Red
        palette_mem[10] = 6'b000001; // Dark Blue
        palette_mem[11] = 6'b100100; // Brown
        palette_mem[12] = 6'b101010; // Gray
        palette_mem[13] = 6'b010101; // Dark Gray
        palette_mem[14] = 6'b111010; // Light Green
        palette_mem[15] = 6'b101111; // Light Blue
    end
    
    // Dual read operations
    always @(posedge clk) begin
        read_data_a <= palette_mem[read_addr_a];
        read_data_b <= palette_mem[read_addr_b];
    end
    
    // Write operation
    always @(posedge clk) begin
        if (write_enable) begin
            palette_mem[write_addr] <= write_data;
        end
    end

endmodule

//========================================
// GOWIN BRAM WRAPPER EXAMPLE
// Example of how to use Gowin primitives if needed
//========================================

// For larger memories, you might want to use Gowin's Block RAM primitives
// Here's an example wrapper for the video memory using Gowin BRAM:

module video_memory_gowin (
    input wire clka,
    input wire clkb, 
    input wire reset_n,
    input wire [16:0] addra,
    input wire [7:0] dina,
    output wire [7:0] douta,
    input wire wea,
    input wire [16:0] addrb,
    output wire [7:0] doutb
);

    // For Gowin GW2AR-18, you would instantiate multiple BRAM blocks
    // and use address decoding to create the full 76800 byte memory
    // This is a simplified example - actual implementation would need
    // multiple BRAM instances with proper address decoding
    
    /*
    BRAM_18K bram_inst_0 (
        .CLKA(clka),
        .CLKB(clkb),
        .RSTA(~reset_n),
        .RSTB(~reset_n),
        .ADDRA(addra[13:0]),    // 16K addresses
        .ADDRB(addrb[13:0]),
        .DIA(dina),
        .DIB(8'h00),
        .DOA(douta),
        .DOB(doutb),
        .WEA(wea),
        .WEB(1'b0)
    );
    */
    
    // For now, use behavioral memory
    video_memory behavioral_mem (
        .clka(clka),
        .clkb(clkb),
        .reset_n(reset_n),
        .addra(addra),
        .dina(dina),
        .douta(douta),
        .wea(wea),
        .addrb(addrb),
        .doutb(doutb)
    );

endmodule
