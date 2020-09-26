`default_nettype none

module i2cd(PHI, CLK1, LED1, LED2, I2C_SDA, I2C_SCL, A, D, MREQ, IORQ, RD, WR, M1, WAIT);
    input       CLK1, PHI, I2C_SCL, MREQ, IORQ, RD, WR, M1;
    input       [19:0] A;
    input       [7:0] D;
    output      LED1, LED2, WAIT;
    inout       I2C_SDA;

    // keep the LEDs blinking along
    poc p0 (PHI, CLK1, LED1, LED2);

    reg [1:0]   idx;
    wire [7:0]  cmd;
    wire [7:0]  data [3:0];
    wire [7:0]  register = data[idx];

    wire i2c_sda_rx, i2c_sda_oe, rw, done;

    assign i2c_sda_rx = I2C_SDA;
    assign I2C_SDA = i2c_sda_oe ? 1'bz : 1'b0;


    i2cslave slave (
        .sda_rx(i2c_sda_rx),
        .sda_oe(i2c_sda_oe),
        .scl(I2C_SCL),
        .data_in(register),
        .data_out(cmd),
        .rw(rw),
        .done(done)
    );

    reg         clear_wait;
    always @(posedge I2C_SCL) begin
        if (done) begin
            if (rw) begin
                idx <= idx + 2'h1;
                if (idx == 2'h3)
                    clear_wait <= 1'b1;
            end else begin
                // any write resets the read index
                idx <= 2'h0;
            end
        end else begin
            clear_wait <= 1'b0;
        end
    end

    reg         clear_edge;
    always @(posedge I2C_SCL) clear_edge <= clear_edge ^ clear_wait;
    reg [2:0]   clear_phi;
    always @(posedge PHI) clear_phi <= {clear_phi[1:0], clear_edge};
    wire        clear_flag = (clear_phi[2] ^ clear_phi[1]);

    // These values are all stable shortly after the CPU begins a memory or
    // I/O cycle, so long as the CPU is being held in a wait state. If an I2C
    // read operation happens when the CPU begins a new bus access cycle, the
    // data may be corrupted - but it would be extraordinarily difficult to
    // run I2C fast enough to make this happen.
    assign data[0] = { MREQ, IORQ, RD, WR, A[19:16] };
    assign data[1] = A[15:8];
    assign data[2] = A[7:0];
    assign data[3] = D;

    // The CPU is put into a wait state when a bus access begins, and released
    // from the wait state when the I2C slave has sent the captured machine
    // state.
    reg waiting;
    reg wait_ready;
    always @(posedge PHI) begin
        if (MREQ && IORQ) begin
            // no bus request is active, get ready to trigger /WAIT
            wait_ready <= 1'b1;
        end else begin
            if (wait_ready) begin
                // if ready to wait, then trigger a wait state
                waiting <= 1'b1;
                wait_ready <= 1'b0;
            end else if (clear_flag) begin
                // only clear waiting if:
                //   (1) already in a bus cycle, and
                //   (2) had already started waiting
                // other clear_flag edges are ignored.
                waiting <= 1'b0;
            end
        end

    end

    assign WAIT = waiting ? 1'b0 : 1'bz;

endmodule
