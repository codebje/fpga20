`default_nettype none

// SPI master - control a w25q32 4mbit Flash module
// 
// How it works
// 
// An instruction begins by driving /CS low. When a word is ready to be
// written, the next bit to write is latched onto MOSI on the falling edge of
// the clock signal and the next bit is latched off MISO on the rising edge.
// When all eight bits have been transferred the clock will remain low.
// Further bytes may be read and written, with the instruction terminated by
// driving /CS high.
//
// The 'active' signal begins a transaction and pulls /CS low immediately. The
// output clock will remain low until the 'send' signal is 

module spi_master(active, sending, clock, out, in, miso, mosi, cs, clk);

input           active;         // is an SPI transaction active?
output          sending;        // high if a transmission is in progress
input           clock;          // input clock source
input  [7:0]    out;            // output data
output [7:0]    in;             // input data

input           miso;
output          mosi;
output          cs;
output          clk;

assign clk = active & sending & clock;

always @(negedge clock) begin
    // if active, 
end

always @(posedge clock) begin
end

endmodule
