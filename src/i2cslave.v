`default_nettype none

// Almost verbatim from https://dlbeer.co.nz/articles/i2c.html

module i2cslave(sda_rx, sda_oe, scl, data_in, data_out, rw, done);

input           sda_rx;         // I2C data pin
output          sda_oe;         // write zero to SDA when this is reset
input           scl;            // I2C clock pin

input  [7:0]    data_in;        // byte of data READ from i2c slave
output [7:0]    data_out;       // byte of data WRITTEN to i2c slave
output          rw;             // was the i2c operation an input or output?
output          done;           // an operation has completed

parameter [6:0] I2C_SLAVE_ADDRESS = 7'h3e;

reg             start;
reg             start_reset;

always @(posedge start_reset or negedge sda_rx) begin
    if (start_reset)
        start <= 1'b0;
    else
        start <= scl;
end

always @(posedge scl) begin
    start_reset <= start;
end

reg             stop;
reg             stop_reset;

always @(posedge stop_reset or posedge sda_rx) begin
    if (stop_reset)
        stop <= 1'b0;
    else
        stop <= scl;
end

always @(posedge scl) begin
    stop_reset <= stop;
end

reg [3:0]       bitcount;

wire            lsb_bit = (bitcount == 4'h7) && !start;
wire            ack_bit = (bitcount == 4'h8) && !start;

always @(negedge scl) begin
    if (ack_bit || start)
        bitcount <= 4'h0;
    else
        bitcount <= bitcount + 4'h1;
end

reg [7:0]       shift;

wire            address_detect = (shift[7:1] == I2C_SLAVE_ADDRESS);
wire            read_write     = shift[0];

always @(posedge scl) begin
    if (!ack_bit)
        shift <= {shift[6:0], sda_rx};
end

reg             master_ack;

always @(posedge scl) begin
    if (ack_bit)
        master_ack <= ~sda_rx;
end

parameter [2:0] STATE_IDLE = 0,
                STATE_ADDR = 1,
                STATE_READ = 2,
                STATE_WRITE = 3;

reg [2:0]       state;
reg             rw_flag;
reg             done_flag;
wire            write_strobe = (state == STATE_WRITE) && ack_bit;

always @(negedge scl) begin
    if (start) begin
        state <= STATE_ADDR;
    end else if (ack_bit) begin
        case (state)
            STATE_IDLE: begin
                state <= STATE_IDLE;
            end
            STATE_ADDR: begin
                if (!address_detect)
                    state <= STATE_IDLE;
                else if (read_write)
                    state <= STATE_READ;
                else
                    state <= STATE_WRITE;
                rw_flag <= read_write;
            end
            STATE_READ: begin
                if (master_ack)
                    state <= STATE_READ;
                else
                    state <= STATE_IDLE;
            end
            STATE_WRITE: begin
                state <= STATE_WRITE;
            end
        endcase
    end
end

reg [7:0]       reg_out;
always @(negedge scl) begin
    if (write_strobe)
        reg_out <= shift;
end

reg             oe;
reg [2:0]       out_bit;
always @(negedge scl) begin
    if (start) begin
        oe <= 1'b1;
        done_flag <= 1'b0;
    end else if (lsb_bit) begin
        oe <= !(((state == STATE_ADDR) && address_detect) || (state == STATE_WRITE));
        done_flag <= (state == STATE_READ) || (state == STATE_WRITE);
    end else if (ack_bit) begin
        done_flag <= 1'b0;
        if (((state == STATE_READ) && master_ack) || ((state == STATE_ADDR) && address_detect && read_write)) begin
            oe <= data_in[7];
            out_bit <= 3'h6;
        end else begin
            oe <= 1'b1;
        end
    end else if (state == STATE_READ) begin
        oe <= data_in[out_bit];
        out_bit <= out_bit - 3'h1;
    end else begin
        oe <= 1'b1;
    end

end

initial oe = 1'b1;

assign sda_oe   = oe;
assign data_out = reg_out;
assign rw       = rw_flag;
assign done     = done_flag;

endmodule
