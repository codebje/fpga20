`default_nettype none

module toplevel(
    PHI,
    CLK1,
    LED1,
    LED2,
    I2C_SDA,
    I2C_SCL,
    INT3,
    INT5,
    INT6,
    INT7,
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

input           CLK1, PHI, I2C_SCL, MREQ, IORQ, RD, WR, M1, SPI_SDI, INT3;
input   [19:0]  A;
inout   [7:0]   D;
output          LED1, LED2, SPI_SS, SPI_SCK, SPI_SDO, INT5, INT6, INT7;
inout           WAIT, I2C_SDA;

wire S0, S1, BOOT;
wire [1:0] leds = { LED1, LED2 };
wire waiting;
wire [7:0] data_out;
wire data_en;

wire spi_sdo,
     spi_sdi,
     spi_sck;
wire [1:0] spi_select;

fpga20 main(
    PHI, CLK1,                          // clocks: inputs
    leds,                               // user LEDs: outputs
    A,                                  // address bus: input
    D,                                  // data bus: input
    data_out,                           // data bus: output
    data_en,                            // data bus: output enable
    IORQ, RD, WR, M1,                   // CPU signals
    waiting,                            // set when /WAIT should be active
    spi_sdo, spi_sdi, spi_sck,          // SPI lines
    spi_select,                         // SPI select line
    S0, S1, BOOT                        // warm boot control
);

// Rewire for I/O board:
//  | SS      | INT5 |
//  | MOSI    | INT6 |
//  | MISO    | INT3 |
//  | SCK     | INT7 |

assign SPI_SDO = spi_select[1] ? 1'bz : spi_sdo;
assign SPI_SCK = spi_select[1] ? 1'bz : spi_sck;
assign INT6 = spi_select[1] ? spi_sdo : 1'bz;
assign INT7 = spi_select[1] ? spi_sck : 1'bz;
assign spi_sdi = spi_select[1] ? INT3 : SPI_SDI;
assign SPI_SS = ~(spi_select == { 0, 1 });
assign INT5 = ~(spi_select == 2'b11);

assign WAIT = waiting ? 0'b0 : 1'bz;
assign D = data_en ? data_out : 8'bz;

SB_WARMBOOT warmboot(
    .BOOT(BOOT),
    .S0(S0),
    .S1(S1)
);

endmodule
