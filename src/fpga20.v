/* verilator lint_off UNUSED */
/* verilator lint_off UNDRIVEN */
module fpga20(PHI, CLK1, LED1, LED2, I2C_SDA, I2C_SCL, A, D, MREQ, IORQ, RD, WR, M1, WAIT, SPI_SDO, SPI_SDI, SPI_SCK, SPI_SS);

input           CLK1, PHI, I2C_SCL, MREQ, IORQ, RD, WR, M1;
inout   [19:0]  A;
inout   [7:0]   D;
output          LED1, LED2, SPI_SS, SPI_SCK;
inout           WAIT, I2C_SDA, SPI_SDI, SPI_SDO;

parameter [15:0] ADDR_STATUS    = 16'h0100,
                 ADDR_SPI_DATA  = 16'h0104,
                 ADDR_SPI_DUAL  = 16'h0105;

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
    status_spi;
wire [7:0] status_reg;
assign status_reg = {
    3'b0, status_spi, status_clk1, status_clk0, status_led1, status_led0
};
initial begin
    status_led0 = 0;
    status_led1 = 0;
    status_clk0 = 1;
    status_clk1 = 1;
    status_spi = 0;
end

wire io_read, io_write, phi_read, phi_edge;
stabilizer stab_io_read(!IORQ & !RD, io_read, CLK1);
stabilizer stab_io_write(!IORQ & !WR, io_write, CLK1);
stabilizer stab_phi(PHI, phi_read, CLK1);
edgedetect edge_phi(phi_read, phi_edge, CLK1);

// SPI control registers: the current SPI mode
parameter SPI_READ      = 1'b0,
          SPI_WRITE     = 1'b1,
          SPI_SINGLE    = 1'b0,
          SPI_DUAL      = 1'b1;
reg spi_direction;
reg spi_mode;
reg [7:0] spi_byte;
reg [2:0] spi_bit;
reg spi_phase;
reg spi_wait;

parameter [1:0] BUS_IDLE        = 2'b00,
                BUS_COMPLETE    = 2'b01,
                BUS_SPI_TXN     = 2'b10;
reg [1:0] bus_state;
initial bus_state = BUS_IDLE;

// FSM model:
// Bus idle - sitting waiting for something interesting from the CPU
//      If we observe an I/O read or write
//              If it's the status port
//                      Read/write status from/to D
//                      Change to bus complete state
//              If it's the SPI single/dual port
//                      Set the bit-counter to 7
//                      If it's a write
//                              Store D in spi_byte
//                              Put the first bit(s) of spi_byte onto MOSI/MISO
//                      Set SPI phase to LATCH
//                      Change to SPI transaction state
// Bus complete - waiting for the CPU to release the bus
//      Change to bus idle state when /MREQ, /IORQ, /RD, /WR all inactive
// SPI transaction state - exchanging data with the Flash memory
//      If SPI phase is latch
//              If reading, latch bit(s) from MISO/MOSI into spi_byte
//              Set phase to shift
//      If SPI phase is shift
//              If writing, move bit(s) from spi_byte onto MOSI/MISO
//              Set phase to latch
//      Decrease bit counter
//      If bit counter was zero at the start of this clock cycle
//              Set state to bus complete
//
task spi_begin();
    bus_state <= BUS_SPI_TXN;
    spi_bit <= 7;
    spi_phase <= 1;
    spi_wait <= 0;
endtask

// CPU bus I/O
always @(posedge CLK1) begin
    read_data_reg <= io_read &&
        (A[15:0] == ADDR_STATUS || A[15:0] == ADDR_SPI_DATA || A[15:0] == ADDR_SPI_DUAL);

    case (bus_state)
        BUS_IDLE: begin
            if (io_read) begin
                case (A[15:0])
                    ADDR_STATUS: begin
                        data_reg <= status_reg;
                        bus_state <= BUS_COMPLETE;
                    end
                    ADDR_SPI_DATA: begin
                        { spi_direction, spi_mode } <= { SPI_READ, SPI_SINGLE };
                        spi_begin();
                    end
                    ADDR_SPI_DUAL: begin
                        { spi_direction, spi_mode } <= { SPI_READ, SPI_DUAL };
                        spi_begin();
                        spi_bit <= 3;
                    end
                    default: ;
                endcase
            end else if (io_write) begin
                case (A[15:0])
                    ADDR_STATUS: begin
                        { status_spi, status_clk1, status_clk0, status_led1, status_led0 } <= D[4:0];
                        bus_state <= BUS_COMPLETE;
                    end
                    ADDR_SPI_DATA: begin
                        { spi_direction, spi_mode } <= { SPI_WRITE, SPI_SINGLE };
                        spi_begin();
                        spi_byte <= D;
                    end
                    ADDR_SPI_DUAL: begin
                        { spi_direction, spi_mode } <= { SPI_WRITE, SPI_DUAL };
                        spi_begin();
                        spi_byte <= D;
                        spi_bit <= 3;
                    end
                    default: ;
                endcase
            end
        end
        BUS_COMPLETE: begin
            if (!io_read && !io_write)
                bus_state <= BUS_IDLE;
        end
        BUS_SPI_TXN: begin
            // modify spi_wait only after detecting a PHI rising edge
            // phi_edge trails the real edge by 20-30ns, and leads the
            // next rising edge by 24-34ns. Altering /WAIT at this
            // moment affords the '1g175 its 3ns setup time, and doesn't
            // require any stabilization back to PHI. The '1g175 will
            // however delay any changes to /WAIT from the CPU until that
            // following edge. A wait state is inserted only if there's
            // more than four bits left to receive in a READ: with four
            // or fewer bits it will take up to 80ns to put data on the
            // bus. After /WAIT is deasserted it will take 14-24ns for
            // the next rising edge of PHI to pass that through, then 1.5PHI
            // or ~81ns before T3 falls. Data must be ready 10ns prior to
            // T3 falling. Between 
            if (phi_edge) begin
                if (spi_direction == SPI_READ && spi_bit > 3) begin
                    spi_wait <= 1;
                end else begin
                    spi_wait <= 0;
                end
            end
            if (spi_phase) begin // latch phase
                if (spi_direction == SPI_READ) begin
                    if (spi_mode == SPI_SINGLE) begin
                        spi_byte[0] <= SPI_SDI;
                    end else begin
                        spi_byte[1:0] <= { SPI_SDI, SPI_SDO };
                    end
                end
                spi_bit <= spi_bit - 1;
            end else begin // shift phase
                if (spi_bit == 7) begin
                    bus_state <= (io_read || io_write) ? BUS_COMPLETE : BUS_IDLE;
                    data_reg <= spi_byte;
                end else begin
                    if (spi_mode == SPI_SINGLE) begin
                        spi_byte <= { spi_byte[6:0], 1'b0 };
                    end else begin
                        spi_byte <= { spi_byte[5:0], 2'b0 };
                    end
                end
            end
            spi_phase <= ~spi_phase;
        end
        default: bus_state <= BUS_IDLE;
    endcase

end

wire spi_sdo_en = bus_state == BUS_SPI_TXN && (spi_direction == SPI_WRITE || spi_mode == SPI_SINGLE);
wire spi_sdi_en = bus_state == BUS_SPI_TXN && (spi_direction == SPI_WRITE && spi_mode == SPI_DUAL);

wire wait_en = (bus_state == BUS_SPI_TXN && spi_wait);

assign WAIT = wait_en ? 0 : 1'bz;
assign D = read_data_reg ? data_reg : 8'bz;
assign SPI_SS = ~status_spi;
assign LED1 = status_clk0 ? blink1 : status_led0;
assign LED2 = status_clk1 ? blink2 : status_led1;
assign SPI_SDO = spi_sdo_en ? (spi_sdi_en ? spi_byte[6] : spi_byte[7]) : 1'bz;
assign SPI_SDI = spi_sdi_en ? spi_byte[7] : 1'bz;
assign SPI_SCK = bus_state == BUS_SPI_TXN & ~spi_phase;

endmodule
