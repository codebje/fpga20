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
    SPI_SELECT,
    warmboot_s0,
    warmboot_s1,
    warmboot);

input           i_clk, i_phi, IORQ, RD, WR, M1, SPI_SDI;
input   [19:0]  i_addr;
input   [7:0]   i_data;
output  [7:0]   o_data;
output  [1:0]   o_leds;
output          o_data_en, SPI_SCK, SPI_SDO, warmboot, waitstate;
output  [1:0]   SPI_SELECT;
output reg      warmboot_s0, warmboot_s1;

parameter [7:0] ADDR_CONTROL   = 8'hf0,        // write: led/warmboot
                ADDR_VERSION   = 8'hf0,        // read: version
                ADDR_SPI_CTRL  = 8'hf1,        // read/write: SPI control
                ADDR_SPI_DATA  = 8'hf2;        // read/write: SPI data

localparam [7:0] VERSION = 8'h10;

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

// Control register
//
// | Bit |  Name  | Purpose                                             |
// | --- | ------ | --------------------------------------------------- |
// |  0  | LED0   | State of User LED 1. Set for ON, reset for OFF.     |
// |  1  | LED1   | State of User LED 2. Set for ON, reset for OFF.     |
// |  2  | CLK0   | Blinks LED0 from 100MHz external oscillator if set. |
// |  3  | CLK1   | Blinks LED1 from CPU clock signal if set.           |
// |  4  | S0     | Warm boot selector S0.                              |
// |  5  | S1     | Warm boot selector S1.                              |
// |  6  | WBOOT  | Warm boot trigger.                                  |
// |  7  |        | Reserved                                            |
reg [1:0] control_led, control_clk;
wire [7:0] control_reg;
assign control_reg = {
    1'b0, 1'b0, warmboot_s1, warmboot_s0, control_clk, control_led
};
reg warmboot_en, warmboot;
initial begin
    control_led = 2'b00;
    control_clk = 2'b11;
    warmboot_s0 = 0;
    warmboot_s1 = 0;
    warmboot_en = 0;
    warmboot = 0;
end

// Delay the warm boot activation signal one clock cycle to allow S0 and S1 to settle.
always @(posedge i_clk) warmboot <= warmboot_en;

// SPI control register
reg spi_enable,
    spi_source,
    spi_busy,
    spi_bulk;
reg [2:0] spi_clock;
wire [7:0] spi_control;
assign spi_control = {
    spi_busy, spi_clock, spi_bulk, 1'b0, spi_source, spi_enable
};
initial begin
    spi_enable = 0;
    spi_source = 0;
    spi_busy = 0;
    spi_bulk = 1;
    spi_clock = 3'b000;
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
reg [7:0] spi_recv, spi_xmit;
reg [2:0] spi_bit;
reg spi_phase;          // clock phase: rising or falling edge
reg spi_command;        // is SPI command filtering active?
reg [7:0] spi_counter;  // counter

wire spi_tick;          // strobe for advancing SPI exchange
edgedetect spi_edge(spi_counter[spi_clock], spi_tick, i_clk);

initial begin
    spi_phase = 0;
    spi_command = 0;
    spi_xmit = 8'hff;
    spi_recv = 8'hff;
    spi_bit = 0;
end

task spi_begin();
    spi_xmit <= i_data;
    spi_counter <= 8'h01;
    spi_phase <= 0;
    spi_busy <= 1;
    spi_bit <= 0;
endtask

parameter [1:0] BUS_IDLE        = 2'b00,
                BUS_COMPLETE    = 2'b01,
                BUS_SPI_TXN     = 2'b10,
                BUS_I2C_TXN     = 2'b11;
reg [1:0] bus_state;
initial bus_state = BUS_IDLE;

// CPU and SPI bus I/O
always @(posedge i_clk) begin
    case (bus_state)
        BUS_IDLE: begin
            if (io_read) begin
                case (addr[7:0])
                    ADDR_VERSION: begin
                        data_reg <= VERSION;
                        read_data_reg <= 1;
                        bus_state <= BUS_COMPLETE;
                    end
                    ADDR_SPI_CTRL: begin
                        data_reg <= spi_control;
                        read_data_reg <= 1;
                        bus_state <= BUS_COMPLETE;
                    end
                    ADDR_SPI_DATA: begin
                        data_reg <= spi_recv;
                        read_data_reg <= 1;
                        bus_state <= BUS_COMPLETE;
                        if (spi_bulk && ~spi_busy) begin
                            spi_xmit <= 8'hff;
                            spi_begin();
                        end
                    end
                    default: ;
                endcase
            end else if (io_write) begin
                case (addr[7:0])
                    ADDR_CONTROL: begin
                        { warmboot_en, warmboot_s1, warmboot_s0, control_clk, control_led } <= i_data[6:0];
                        bus_state <= BUS_COMPLETE;
                    end
                    ADDR_SPI_CTRL: begin
                        // spi_command is set if slave select on the Flash ROM
                        // is pulled low
                        spi_command <= i_data[1:0] != { spi_source, spi_enable } && i_data[1:0] == 2'b01;
                        { spi_clock, spi_bulk, spi_source, spi_enable } <= { i_data[6:3], i_data[1:0] };
                        bus_state <= BUS_COMPLETE;
                    end
                    ADDR_SPI_DATA: begin
                        if (!spi_busy) begin
                            if (spi_command && (i_data == 8'h3b || i_data == 8'h6B || i_data == 8'hEB || i_data == 8'hBB
                                || i_data == 8'h77 || i_data == 8'h32 || i_data == 8'h92 || i_data == 8'h94)) begin
                                spi_enable <= 0;
                                spi_command <= 0;
                            end else begin
                                spi_xmit <= i_data;
                                spi_command <= 0;
                                spi_begin();
                            end
                        end
                        bus_state <= BUS_COMPLETE;
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
        default: bus_state <= BUS_IDLE;
    endcase

    if (spi_busy) begin
        if (spi_tick || spi_clock == 0) begin
            if (spi_phase) begin
                // latch an input bit
                spi_recv <= { spi_recv[6:0], SPI_SDI };
                // shift an output bit
                spi_xmit <= { spi_xmit[6:0], 1'b1 };
                if (spi_bit == 7) begin
                    spi_busy <= 0;
                end
                spi_bit <= spi_bit + 1;
            end
            spi_phase <= ~spi_phase;
        end
        spi_counter[7:1] <= spi_counter[7:1] + 1;
    end
end

/*
    case (bus_state)
        BUS_IDLE: begin
            end else if (io_write) begin
                spi_direction <= SPI_WRITE;
                case (addr[15:0])
                    ADDR_STATUS: begin
                        spi_command <= (~status_spi & i_data[4] & ~i_data[5]) | (status_spi & status_source & ~i_data[5]);
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
                            spi_port <= 0;
                            spi_clock <= 0;
                        end
                    end

                    ADDR_SPI_DATA2: begin
                        { spi_output, spi_byte[7:0] } <= { i_data, 1'b1 };
                        bus_state <= BUS_SPI_TXN;
                        spi_command <= 0;
                        spi_port <= 1;
                        spi_clock <= 0;
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
            if (spi_tick) begin
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
            if (spi_clock == (spi_port ? 4 : 0)) begin
                spi_clock <= 0;
                spi_tick <= 1;
            end else begin
                spi_clock <= spi_clock + 1;
                spi_tick <= 0;
            end
        end
        default: bus_state <= BUS_IDLE;
    endcase
end
*/

assign waitstate = 0;

assign o_data = data_reg;
assign o_data_en = read_data_reg;
assign SPI_SELECT = { spi_source, spi_enable };
assign o_leds[0] = control_clk[0] ? blink1 : control_led[0];
assign o_leds[1] = control_clk[1] ? blink2 : control_led[1];
assign SPI_SDO = spi_xmit[7];
assign SPI_SCK = spi_phase;

endmodule
