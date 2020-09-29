#include <stdlib.h>
#include "Vfpga20.h"
#include "verilated.h"

#include "signal.h"
#include "peripheral.h"
#include "spiflash.h"

#include <vector>
#include <algorithm>
#include <iterator>
#include <iostream>

using namespace std;

#define PHI_FREQ        18.432
#define OSC_FREQ        100.0

const int IO_STATUS       = 0x100;
const int IO_SPI_DATA     = 0x104;

// test I/O ops: write <byte> to <address>, read <byte> from <address>
// An I/O op will take four PHI cycles:
//    Initial: address lines set to <address>, data high, /IORQ, /MREQ, /RD, /WR, /M1 high
//    T1 falls: /IORQ low, /RD low for reads, data to <byte> for writes
//    T2 rises: /WR low for writes
//    T2 falls: sample /WAIT
//    TW falls: sample /WAIT
//    T3 falls: latch data for reads, /IORQ, /RD, /WR go high, data goes high

enum cpu_op { IORead, IOWrite, };
enum cpu_cycle { T1, T2, TW, T3 };

typedef struct bus_state {
    cpu_op      op;
    vluint32_t  address;
    vluint8_t   byte;
} bus_state;

const vector<bus_state> states(
    {
        { IORead, IO_STATUS, 0x0C },            // after reset the FPGA auto-blinks the LEDs
        { IOWrite, IO_STATUS, 0x00 },           // disable auto-blink
        { IORead, IO_STATUS, 0x00 },            // confirm it stuck
        { IOWrite, IO_SPI_DATA, 0x90 },         // write manufacturer code command
        { IORead, IO_STATUS, 0x20 },            // SPITX should be set
        { IOWrite, IO_STATUS, 0x00 },           // "clear" it
        { IORead, IO_STATUS, 0x20 },            // SPITX should still be set - it's read-only
        { IOWrite, IO_STATUS, 0x10 },           // Enable SPI transmission
    }
);

int main(int argc, char **argv) {
    // Initialize Verilators variables
    Verilated::commandArgs(argc, argv);

    // Create an instance of our module under test
    Vfpga20 *tb = new Vfpga20;

    // Clock states
    double elapsed = 0.0;
    long phi_ticks = 1;
    long osc_ticks = 1;
    vluint8_t phi_state = 0;
    vluint8_t osc_state = 0;

    // Peripherals
    vector<peripheral*> peripherals;
    spiflash flash;

    peripherals.push_back(&flash);

    // Bus state: iterate along table
    auto state = states.begin();
    cpu_cycle cycle = T1;

    // "reset" the CPU
    tb->IORQ = tb->MREQ = tb->RD = tb->WR = tb->M1 = 1;

    // Tick the clock until we are done
    while(state < states.end()) {
        bool phi_clocked = false;

        double next_phi = phi_ticks/PHI_FREQ;
        double next_osc = osc_ticks/OSC_FREQ;
        if (next_phi < next_osc) {
            elapsed = next_phi;
            phi_ticks++;
            phi_state = 1 - phi_state;
            tb->PHI = phi_state;
            phi_clocked = true;
            //printf("PHI <- %d, A=%05x D=%02X MREQ=%d IORQ=%d RD=%d WR=%d LED1=%d LED2=%d\n",
                    //phi_state, tb->A, tb->D, tb->MREQ, tb->IORQ, tb->RD, tb->WR, tb->LED1, tb->LED2);
        } else {
            elapsed = next_osc;
            osc_ticks++;
            osc_state = 1 - osc_state;
            tb->CLK1 = osc_state;
        }

        tb->eval();
        for (peripheral *p : peripherals) {
            p->eval(tb, elapsed);
        }

        // check for edges on signals of interest

        if (phi_clocked) {
            switch (cycle) {
                case T1:
                    if (phi_state) {
                        tb->A = state->address;
                    }
                    // check for falling edge
                    if (!phi_state) {
                        // T1 falls: /IORQ low, /RD low for reads, data to <byte> for writes
                        tb->IORQ = 0;
                        if (state->op == IORead) tb->RD = 0;
                        if (state->op == IOWrite) tb->D = state->byte;
                        if (state->op == IOWrite)
                            printf("IO write: %04x = %02x\n", tb->A & 0xffff, tb->D);
                        cycle = T2;
                    }
                    break;
                case T2:
                    // T2 rises: /WR low for writes
                    if (phi_state && state->op == IOWrite) {
                        tb->WR = 0;
                    }
                    if (!phi_state) {
                        cycle = TW;
                    }
                    // TODO T2 falls: sample /WAIT
                    break;
                case TW:
                    if (!phi_state) {
                        cycle = T3;
                    }
                    //    TW falls: sample /WAIT
                    break;
                case T3:
                    if (!phi_state) {
                        // T3 falls: latch data for reads, /IORQ, /RD, /WR go high, data goes high
                        if (state->op == IORead) {
                            printf("IO read: %04x = %02x\n", tb->A & 0xffff, tb->D);
                            if (tb->D != state->byte) {
                                printf("IO read is incorrect: got %u instead of %u in PHI cycle %ld\n",
                                        tb->D, state->byte, phi_ticks);
                            }
                        }
                        state++;
                        cycle = T1;
                        tb->IORQ = tb->RD = tb->WR = 1;
                        tb->D = 0xff;
                    }
                    break;
            }
        }
    }

    exit(EXIT_SUCCESS);
}
