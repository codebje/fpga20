`default_nettype none

module stabilizer(in, out, clk);

input in, clk;
output out;

reg [1:0] stabilizers;

always @(posedge clk) stabilizers <= { stabilizers[0], in };

assign out = stabilizers[1];

endmodule
