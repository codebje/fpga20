`default_nettype none

module toplevel(
    PHI,
    CLK1,
    LED1,
    LED2,
    I2C_SDA,
    I2C_SCL,
    A,
    D,
    MREQ,
    IORQ,
    RD,
    WR,
    M1,
    WAIT,
    SPI_SDO,
    SPI_SDI,
    SPI_SCK,
    SPI_SS
);

input           CLK1, PHI, I2C_SCL, MREQ, IORQ, RD, WR, M1, SPI_SDI;
input   [19:0]  A;
inout   [7:0]   D;
output          LED1, LED2, SPI_SS, SPI_SCK, SPI_SDO;
inout           WAIT, I2C_SDA;

wire S0, S1, BOOT;
wire [1:0] leds = { LED1, LED2 };
wire waiting;
wire [7:0] data_out;
wire data_en;

fpga20 main(
    PHI, CLK1,                          // clocks: inputs
    leds,                               // user LEDs: outputs
    A,                                  // address bus: input
    D,                                  // data bus: input
    data_out,                           // data bus: output
    data_en,                            // data bus: output enable
    IORQ, RD, WR, M1,                   // CPU signals
    waiting,                            // set when /WAIT should be active
    SPI_SDO, SPI_SDI, SPI_SCK, SPI_SS,  // SPI lines
    S0, S1, BOOT                        // warm boot control
);

assign WAIT = waiting ? 0'b0 : 1'bz;
assign D = data_en ? data_out : 8'bz;

SB_WARMBOOT warmboot(
    .BOOT(BOOT),
    .S0(S0),
    .S1(S1)
);

endmodule
