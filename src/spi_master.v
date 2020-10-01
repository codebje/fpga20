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

reg [2:0]       index;
reg [7:0]       in;
reg             ack;
reg             out;

assign DAT_O = in;
assign cs = !CYC_I;
assign ACK_O = ack;
assign mosi = out;

reg transfer;
initial transfer = 0;
initial index = 7;

reg outclk;

assign clk = outclk;//transfer & ~CLK_I;

// rising edge: shift
always @(posedge CLK_I) begin
    if (RST_I) begin
        transfer <= 0;
        index <= 7;
        ack <= 0;
    end else if (transfer) begin
        if (outclk) begin
            index <= index - 1;
            out <= DAT_I[index];
            if (index == 7) begin
                transfer <= 0;
                ack <= 1;
                out <= 0;
            end else begin
                ack <= 0;
            end
        end else begin
            in <= { in[6:0], miso };
        end
        outclk <= ~outclk;
    end else if (CYC_I & STB_I & !ack) begin
        out <= DAT_I[7];
        transfer <= 1;
        index <= 6;
        outclk <= 0;
    end else begin
        transfer <= 0;
        ack <= 0;
        index <= 7;
        outclk <= 0;
    end
end

// falling edge: latch
always @(negedge CLK_I) begin
    if (transfer) begin
    end else begin
    end
end

endmodule
