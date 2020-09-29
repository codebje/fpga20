/* verilator lint_off UNUSED */
/* verilator lint_off UNDRIVEN */
module fpga20(PHI, CLK1, LED1, LED2, I2C_SDA, I2C_SCL, A, D, MREQ, IORQ, RD, WR, M1, WAIT, SPI_SDO, SPI_SDI, SPI_SCK, SPI_SS);

input           CLK1, PHI, I2C_SCL, MREQ, IORQ, RD, WR, M1, SPI_SDI;
inout   [19:0]  A;
inout   [7:0]   D;
output          LED1, LED2, SPI_SDO, SPI_SS, SPI_SCK;
inout           WAIT;
inout           I2C_SDA;

// keep the LEDs blinking along
wire blink1, blink2;
poc p0 (PHI, CLK1, blink1, blink2);

// I/O read line
reg read_data_reg;
reg [7:0] data_reg;

// Status register
reg status_led0,
    status_led1,
    status_clk0,
    status_clk1,
    status_spi,
    status_spitx,
    status_spirx,
    status_spidir;
wire [7:0] status_reg;
assign status_reg = {
    status_spidir, status_spirx, status_spitx, status_spi,
    status_clk1, status_clk0, status_led1, status_led0
};
initial begin
    status_led0 = 0;
    status_led1 = 0;
    status_clk0 = 0;
    status_clk1 = 0;
    status_spi = 0;
    status_spitx = 0;
    status_spirx = 0;
    status_spidir = 0;
end

assign LED1 = status_clk0 ? blink1 : status_led0;
assign LED2 = status_clk1 ? blink2 : status_led1;

reg io_read;
stabilizer stab_io_read(!IORQ & !RD, io_read, CLK1);
wire io_write = !IORQ & !WR;

reg [7:0] spi_xmit_byte;
reg [7:0] spi_recv_byte;

// CPU bus I/O
always @(posedge PHI) begin
    read_data_reg <= 0;

    if (io_read) begin
        case (A[15:0])
            16'h0100: begin
                read_data_reg <= 1;
                data_reg <= status_reg;
            end
            16'h0104: begin
                status_spirx <= 0;
                read_data_reg <= 1;
                data_reg <= spi_recv_byte;
            end
            default: ;
        endcase
    end else if (io_write) begin
        case (A[15:0])
            16'h0100: begin
                { status_spi, status_clk1, status_clk0, status_led1, status_led0 } <= D[4:0];
                status_spidir <= D[7];
            end
            16'h0104: begin
                // if SPITX is already set, this write is lost
                if (!status_reg[5]) begin
                    spi_xmit_byte <= D;
                    status_spitx <= 1;
                end
            end
            default: ;
        endcase
    end
end

// SPI driver
reg             spi_i_ack;
wire            spi_o_clk = CLK1;
reg             spi_o_rst;
reg             spi_o_stb;
reg             spi_o_cyc;
reg             spi_o_we;
reg     [7:0]   spi_i_dat;
reg     [7:0]   spi_o_dat;
spi_master flash(
    spi_i_ack,
    spi_o_clk,
    spi_o_dat,
    spi_i_dat,
    spi_o_rst,
    spi_o_stb,
    spi_o_cyc,
    spi_o_we,
    SPI_SDI,
    SPI_SDO,
    SPI_SS,
    SPI_SCK);

initial begin
    spi_o_cyc = 0;
    spi_o_stb = 0;
    spi_o_rst = 0;
    spi_o_we  = 0;
end

// States:
//   Inactive - CYC=0, waiting on status[4] set
//   Idle - CYC=1, STB=0, the WISHBONE bus is active with no request active
//   - waiting on TX/RX ready
//   Request - CYC=STB=1, bus request is active - waiting on ACK=1

always @(posedge CLK1) begin
    if (spi_o_cyc) begin
        if (spi_o_stb) begin
            // wait on an ack
            if (spi_i_ack) begin
                spi_o_stb <= 0;
                spi_recv_byte <= spi_i_dat;
                status_spirx <= 1;
                status_spitx <= 0;
            end
        end else begin
            if (!status_spi) begin
                // finish the transfer
                spi_o_cyc <= 0;
                spi_o_stb <= 0;
                spi_o_we <= 0;
                spi_o_rst <= 0;
            end else if (!status_spidir && status_spitx) begin
                // SPIDIR=xmit, SPITX set
                spi_o_dat <= spi_xmit_byte;
                status_spitx <= 0;
                spi_o_stb <= 1;
                spi_o_we <= 1;
            end else if (status_spidir && !status_spirx) begin
                // SPIDIR=recv, SPIRX reset
                spi_o_dat <= spi_xmit_byte;
                spi_o_stb <= 1;
                spi_o_we <= 0;
            end
        end
    end else begin
        // The only thing that happens here is the cycle begins if enabled
        spi_o_cyc <= status_spi;
    end
end

assign WAIT = PHI ? 1'b1 : 1'bz;

assign D = read_data_reg ? data_reg : 8'bz;

endmodule
