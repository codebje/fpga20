`default_nettype none

// Proof-of-concept LED blinker.
//
// This module takes in what in theory is a 100MHz clock signal and divides
// it down to a ~1.49Hz signal (100MHz/2^26), and blinks an LED at that rate.
//
// The other LED divides 18.432MHz by 2^24, for a ~1.09Hz signal.
//
//
module poc(c1, c2, o1, o2);

    input       c1, c2;
    output      o1, o2;

    reg [23:0]  counter1;
    reg [25:0]  counter2;

    always @(posedge c1)
        counter1 <= counter1 + 1'b1;

    always @(posedge c2)
        counter2 <= counter2 + 1'b1;

    assign o1 = counter1[23];
    assign o2 = counter2[25];

endmodule

