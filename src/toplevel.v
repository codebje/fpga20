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
inout   [19:0]  A;
inout   [7:0]   D;
output          LED1, LED2, SPI_SS, SPI_SCK, SPI_SDO;
inout           WAIT, I2C_SDA;

wire S0, S1, BOOT;

fpga20 main(PHI, CLK1, LED1, LED2, I2C_SDA, I2C_SCL, A, D, MREQ, IORQ, RD, WR, M1, WAIT, SPI_SDO, SPI_SDI, SPI_SCK, SPI_SS, S0, S1, BOOT);

SB_WARMBOOT warmboot(
    .BOOT(BOOT),
    .S0(S0),
    .S1(S1)
);

endmodule
