`default_nettype none

// SPI master - control a w25q32 4mbit Flash module
// 
// WISHBONE DATASHEET
// General description:         WISHBONE SLAVE interface, revision level B4
// Supported cycles:            SLAVE, READ/WRITE
//                              SLAVE, BLOCK READ/WRITE
//                              SLAVE, RMW
// Data port size:              8-bit
// Data port granularity:       8-bit
// Maximum operand size:        8-bit
// Data transfer ordering:      BIG/LITTLE ENDIAN
// Data transfer sequencing:    UNDEFINED
// Signals:                     ACK_O
//                              CLK_I
//                              DAT_I[7:0]
//                              DAT_O[7:0]
//                              RST_I
//                              STB_I
//                              CYC_I
//                              WE_I

/* verilator lint_off UNUSED */
module spi_master(ACK_O, CLK_I, DAT_I, DAT_O, RST_I, STB_I, CYC_I, WE_I, miso, mosi, cs, clk);

input           CLK_I, RST_I, STB_I, CYC_I, WE_I, miso;
output          ACK_O, mosi, cs, clk;
input  [7:0]    DAT_I;
output [7:0]    DAT_O;

assign ACK_O = 1'b0;
assign DAT_O = 8'b0;
assign mosi = 1'b0;
assign cs = 1'b1;
assign clk = CLK_I;

always @(negedge CLK_I) begin
end

always @(posedge CLK_I) begin
end

endmodule
