`default_nettype none

/* verilator lint_off UNUSED */
module fpga20(
    i_phi,              // CPU clock: 18.432MHz
    i_clk,              // FPGA clock: 100MHz
    o_leds,             // user
    i_addr,             // address bus
    i_data,             // data bus in
    o_data,             // data bus out
    o_data_en,          // write enable for o_data
    IORQ,
    RD,
    WR,
    M1,
    waitstate,
    SPI_SDO,
    SPI_SDI,
    SPI_SCK,
    SPI_SS,
    warmboot_s0,
    warmboot_s1,
    warmboot);

input           i_clk, i_phi, IORQ, RD, WR, M1, SPI_SDI;
input   [19:0]  i_addr;
input   [7:0]   i_data;
output  [7:0]   o_data;
output  [1:0]   o_leds;
output          o_data_en, SPI_SS, SPI_SCK, SPI_SDO, warmboot, waitstate;
output reg      warmboot_s0, warmboot_s1;

parameter [15:0] ADDR_STATUS    = 16'h0100,
                 ADDR_VERSION   = 16'h0101,
                 ADDR_SPI_DATA  = 16'h0104;

localparam [7:0] VERSION = 8'd1;

// keep the LEDs blinking along
wire blink1, blink2;
leds p0 (i_phi, i_clk, blink1, blink2);

// I/O read line
reg read_data_reg;
reg [7:0] data_reg;
initial begin
    read_data_reg = 0;
    data_reg = 8'hff;
end

// Status register
reg status_led0,
    status_led1,
    status_clk0,
    status_clk1,
    status_spi,
    warmboot_en,
    warmboot;
wire [7:0] status_reg;
assign status_reg = {
    1'b0, warmboot_s1, warmboot_s0, status_spi,
    status_clk1, status_clk0, status_led1, status_led0
};
initial begin
    status_led0 = 0;
    status_led1 = 0;
    status_clk0 = 1;
    status_clk1 = 1;
    status_spi = 0;
    warmboot_s0 = 0;
    warmboot_s1 = 0;
    warmboot_en = 0;
    warmboot = 0;
end

wire io_read, io_write, phi_read, phi_edge;
stabilizer stab_io_read(!IORQ & !RD, io_read, i_clk);
stabilizer stab_io_write(!IORQ & !WR, io_write, i_clk);
stabilizer stab_phi(i_phi, phi_read, i_clk);
edgedetect edge_phi(phi_read, phi_edge, i_clk);
wire [19:0] addr;
generate
    genvar i;
    for (i = 0; i < 20; i++) begin
        stabilizer astab(i_addr[i], addr[i], i_clk);
    end
endgenerate

// SPI control registers: the current SPI mode
parameter SPI_READ      = 1'b0,
          SPI_WRITE     = 1'b1;
reg spi_direction;
reg [7:0] spi_byte;
reg [2:0] spi_bit;
reg spi_output;
reg spi_phase;
reg spi_wait;
reg spi_command;

initial begin
    spi_output = 1;
    spi_phase = 0;
    spi_wait = 0;
    spi_command = 0;
    spi_byte = 8'hff;
    spi_bit = 0;
end

parameter [1:0] BUS_IDLE        = 2'b00,
                BUS_COMPLETE    = 2'b01,
                BUS_SPI_TXN     = 2'b10,
                BUS_I2C_TXN     = 2'b11;
reg [1:0] bus_state;
initial bus_state = BUS_IDLE;

task spi_begin();
endtask

// Delay the warm boot activation signal one clock cycle to allow S0 and S1 to settle.
always @(posedge i_clk) warmboot <= warmboot_en;

// Wait state control
always @(posedge i_clk) begin
    // Changes to /WAIT need to be at least 3ns before PHI rises, as there's a '1g175 FF clocking changes through to
    // the CPU. The phi_edge signal trails the real rising edge by 20-30ns, and leads the next rising edge by 24-34ns.
    // This gives plenty of time for a change to /WAIT to settle before the '1g175 clocks it in.
    if (phi_edge) begin
        // Hold /WAIT while the SPI transaction is in progress. Due to the '1g175 this will add a spurious wait to
        // the CPU's pipeline; having a flag to indicate an SPI transaction has less than 80ns to go would allow a
        // more efficient alteration of /WAIT.
        spi_wait <= (bus_state == BUS_SPI_TXN) || (bus_state == BUS_IDLE && io_write && addr[15:0] == ADDR_SPI_DATA);
    end
end

// CPU and SPI bus I/O
always @(posedge i_clk) begin
    case (bus_state)
        BUS_IDLE: begin
            if (io_read) begin
                spi_direction <= SPI_READ;
                case (addr[15:0])
                    ADDR_STATUS: begin
                        data_reg <= status_reg;
                        read_data_reg <= 1;
                        bus_state <= BUS_COMPLETE;
                    end
                    ADDR_VERSION: begin
                        data_reg <= VERSION;
                        read_data_reg <= 1;
                        bus_state <= BUS_COMPLETE;
                    end
                    ADDR_SPI_DATA: begin
                        bus_state <= BUS_SPI_TXN;
                        spi_byte <= 0;
                    end
                    default: ;
                endcase
            end else if (io_write) begin
                spi_direction <= SPI_WRITE;
                case (addr[15:0])
                    ADDR_STATUS: begin
                        spi_command <= ~status_spi & i_data[4];
                        { warmboot_en, warmboot_s1, warmboot_s0, status_spi,
                            status_clk1, status_clk0, status_led1, status_led0 } <= i_data;
                        bus_state <= BUS_COMPLETE;
                    end
                    ADDR_SPI_DATA: begin
                        if (spi_command && (i_data == 8'h3b || i_data == 8'h6B || i_data == 8'hEB || i_data == 8'hBB
                            || i_data == 8'h77 || i_data == 8'h32 || i_data == 8'h92 || i_data == 8'h94)) begin
                            // These command words are all forbidden: disable
                            // SPI if they're encountered. They're all dual or
                            // quad I/O which would result in the FPGA and the
                            // Flash IC shorting each other on SPI_SDI.
                            status_spi <= 0;
                            bus_state <= BUS_COMPLETE;
                        end else begin
                            { spi_output, spi_byte[7:0] } <= { i_data, 1'b1 };
                            bus_state <= BUS_SPI_TXN;
                            spi_command <= 0;
                        end
                    end
                    default: ;
                endcase
            end
        end
        BUS_COMPLETE: begin
            if (!io_read && !io_write) begin
                read_data_reg <= 0;
                bus_state <= BUS_IDLE;
            end
        end
        BUS_SPI_TXN: begin
            // The SPI code is contained in this always block to avoid two clock delays on every transfer
            // for strobe signalling.
            if (spi_phase) begin
                // if the clock is RISING, latch input
                // moved here because SPI_SCK is one clock cycle behind
                spi_byte[0] <= SPI_SDI;
                // if the clock is FALLING, shift data
                { spi_output, spi_byte[7:1] } <= spi_byte;
                if (spi_direction != SPI_WRITE) begin
                    spi_output <= 1;
                end
                if (spi_bit == 7) begin
                    bus_state <= BUS_COMPLETE;
                    data_reg <= { spi_byte[6:0], SPI_SDI };
                    read_data_reg <= spi_direction == SPI_READ;
                end
                spi_bit <= spi_bit + 1;
            end
            spi_phase <= ~spi_phase;
        end
        default: bus_state <= BUS_IDLE;
    endcase
end

assign waitstate = spi_wait;

assign o_data = data_reg;
assign o_data_en = read_data_reg;
assign SPI_SS = ~status_spi;
assign o_leds[0] = status_clk0 ? blink1 : status_led0;
assign o_leds[1] = status_clk1 ? blink2 : status_led1;
assign SPI_SDO = spi_output;
assign SPI_SCK = spi_phase;

endmodule
