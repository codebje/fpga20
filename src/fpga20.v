module fpga20(PHI, CLK1, LED1, LED2, I2C_SDA, I2C_SCL, A, D, MREQ, IORQ, RD, WR, M1, WAIT, SPI_SDO, SPI_SDI, SPI_SCK, SPI_SS);

input           CLK1, PHI, I2C_SCL, MREQ, IORQ, RD, WR, M1, SPI_SDI;
input   [19:0]  A;
input   [7:0]   D;
output          LED1, LED2, WAIT, SPI_SDO, SPI_SS, SPI_SCK;
inout           I2C_SDA;

// keep the LEDs blinking along
poc p0 (PHI, CLK1, LED1, LED2);

// SPI driver
reg             spi_active;
reg             spi_sending;
reg     [7:0]   spi_output;
reg     [7:0]   spi_input;
spi_master master (spi_active, spi_sending, CLK1, spi_output, spi_input, SPI_SDI, SPI_SDO, SPI_SS, SPI_SCK);
assign spi_active = 0;

assign WAIT = 1'bz;

endmodule
