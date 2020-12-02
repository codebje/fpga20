#include <stdlib.h>
#include "Vfpga20.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#include "signal.h"
#include "peripheral.h"
#include "spiflash.h"

#include <vector>
#include <algorithm>
#include <iterator>
#include <iostream>
#include <iomanip>

using namespace std;

#define PHI_FREQ        18.432
#define OSC_FREQ        100.0

const int IO_CONTROL    = 0xf0;
const int IO_SPI_CTRL   = 0xf1;
const int IO_SPI_DATA   = 0xf2;
const int IO_VERSION    = 0xf3;

const int MIN_WAITS     = 1;

// test I/O ops: write <byte> to <address>, read <byte> from <address>
// An I/O op will take four PHI cycles:
//    Initial: address lines set to <address>, data high, /IORQ, /MREQ, /RD, /WR, /M1 high
//    T1 falls: /IORQ low, /RD low for reads, data to <byte> for writes
//    T2 rises: /WR low for writes
//    T2 falls: sample /WAIT
//    TW falls: sample /WAIT
//    T3 falls: latch data for reads, /IORQ, /RD, /WR go high, data goes high

enum cpu_op { IORead, IOWrite, Cycle };
enum cpu_cycle { T1, T2, TW, T3 };

typedef struct bus_state {
    cpu_op      op;
    vluint32_t  address;
    vluint8_t   byte;
    string      desc;
} bus_state;

const vector<bus_state> states(
    {
        { IORead, IO_VERSION, 0x11,     "Read version register" },
        { IOWrite, IO_SPI_DATA, 0x90,   "Write SPI manufacturer code command (should not have effect)" },

        { IOWrite, IO_SPI_CTRL, 0x01,   "Enable SPI transaction" },
        { IORead, IO_SPI_CTRL, 0x01,    "SPI enabled and not busy" },
        { IOWrite, IO_SPI_DATA, 0x90,   "Write SPI manufacturer code command" },
        { IORead, IO_SPI_CTRL, 0x01,    "SPI enabled and not busy" },
        { IOWrite, IO_SPI_DATA, 0x00,   "Write SPI address 23-16" },
        { IORead, IO_SPI_CTRL, 0x01,    "SPI enabled and not busy" },
        { IOWrite, IO_SPI_DATA, 0x00,   "Write SPI address 15-08" },
        { IORead, IO_SPI_CTRL, 0x01,    "SPI enabled and not busy" },
        { IOWrite, IO_SPI_DATA, 0x00,   "Write SPI address 07-00" },
        { IORead, IO_SPI_CTRL, 0x01,    "SPI enabled and not busy" },
        { IOWrite, IO_SPI_CTRL, 0x09,   "Enable bulk read mode" },
        { IOWrite, IO_SPI_DATA, 0xff,   "Write SPI dummy byte" },
        { IORead, IO_SPI_DATA, 0xef,    "Read manufacturer ID" },
        { IORead, IO_SPI_CTRL, 0x09,    "SPI enabled and not busy" },
        { IORead, IO_SPI_DATA, 0x15,    "Read device ID" },
        { IORead, IO_SPI_CTRL, 0x09,    "SPI enabled and not busy" },

        { IOWrite, IO_SPI_CTRL, 0x00,   "Disable SPI transaction" },
        { IOWrite, IO_SPI_CTRL, 0x01,   "Enable SPI transaction" },
        { IOWrite, IO_SPI_DATA, 0x92,   "Write SPI manufacturer code dual-I/O command" },
        { IORead, IO_SPI_CTRL, 0x00,    "Confirm dual-I/O command disabled SPI" },

        { IOWrite, IO_SPI_CTRL, 0x01,   "Enable SPI transaction" },
        { IOWrite, IO_SPI_DATA, 0x90,   "Write SPI manufacturer code command" },
        { IORead, IO_SPI_CTRL, 0x01,    "SPI enabled and not busy" },

        { IOWrite, IO_SPI_CTRL, 0x00,   "Disable SPI transaction" },
        { IOWrite, IO_SPI_CTRL, 0x11,   "Enable 25MHz SPI" },
        { IOWrite, IO_SPI_DATA, 0x90,   "Write SPI manufacturer code command" },
        { IORead, IO_SPI_CTRL, 0x91,    "SPI enabled and is busy" },
        { IORead, IO_SPI_CTRL, 0x11,    "SPI enabled and not busy" },

        { IOWrite, IO_SPI_CTRL, 0x00,   "Disable SPI transaction" },
        { IOWrite, IO_SPI_CTRL, 0x11,   "Enable 25MHz SPI" },
        { IOWrite, IO_SPI_DATA, 0x90,   "Write SPI manufacturer code command" },
        { IORead, IO_SPI_CTRL, 0x91,    "SPI enabled and is busy" },
        { IORead, IO_SPI_CTRL, 0x11,    "SPI enabled and not busy" },

        { IOWrite, IO_SPI_CTRL, 0x00,   "Disable SPI transaction" },
        { IOWrite, IO_SPI_CTRL, 0x21,   "Enable 12.5MHz SPI" },
        { IOWrite, IO_SPI_DATA, 0x90,   "Write SPI manufacturer code command" },
        { IORead, IO_SPI_CTRL, 0xa1,    "SPI enabled and is busy" },
        { Cycle, 0, 1,                  "Wait one machine cycle" },
        { IORead, IO_SPI_CTRL, 0xa1,    "SPI enabled and is busy" },
        { IORead, IO_SPI_CTRL, 0x21,    "SPI enabled and not busy" },

        { IOWrite, IO_SPI_CTRL, 0x00,   "Disable SPI transaction" },
        { IOWrite, IO_SPI_CTRL, 0x31,   "Enable 6.25MHz SPI" },
        { IOWrite, IO_SPI_DATA, 0x90,   "Write SPI manufacturer code command" },
        { IORead, IO_SPI_CTRL, 0xb1,    "SPI enabled and is busy" },
        { Cycle, 0, 3,                  "Wait three machine cycles" },
        { IORead, IO_SPI_CTRL, 0xb1,    "SPI enabled and is busy" },
        { IORead, IO_SPI_CTRL, 0x31,    "SPI enabled and not busy" },

        { IOWrite, IO_SPI_CTRL, 0x00,   "Disable SPI transaction" },
        { IOWrite, IO_SPI_CTRL, 0x73,   "Enable 400kHz SPI" },
        { IOWrite, IO_SPI_DATA, 0x90,   "Write SPI manufacturer code command" },
        { IORead, IO_SPI_CTRL, 0xf3,    "SPI enabled and is busy" },
        { Cycle, 0, 89,                "Wait 100 machine cycles" },
        { IORead, IO_SPI_CTRL, 0xf3,    "SPI enabled and is busy" },
        { IORead, IO_SPI_CTRL, 0x73,    "SPI enabled and not busy" },

        { IORead, 0x00, 0xff,           "Dummy read to extend trace" },
    }
);

inline bool is_atty(const std::ostream& stream)
{
    return &stream == &std::cout && isatty(fileno(stdout));
}

inline std::ostream& success(std::ostream& stream)
{
    if (is_atty(stream)) {
        stream << "\033[32m OK\033[00m";
    } else {
        stream << " OK";
    }
    return stream;
}

inline std::ostream& failure(std::ostream& stream)
{
    if (is_atty(stream)) {
        stream << "\033[31m FAIL\033[00m";
    } else {
        stream << " FAIL";
    }
    return stream;
}

int main(int argc, char **argv) {
    // Initialize Verilators variables
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    // Create an instance of our module under test
    Vfpga20 *tb = new Vfpga20;
    VerilatedVcdC *tfp = new VerilatedVcdC;
    tb->trace(tfp, 99);
    tfp->open("main.vcd");

    // Clock states
    double elapsed = 0.0;
    vluint64_t tick = 0;
    long phi_ticks = 1;
    long osc_ticks = 1;
    vluint8_t phi_state = 0;
    vluint8_t osc_state = 0;
    int wait_cycles = 0;

    // Peripherals
    vector<peripheral*> peripherals;
    spiflash flash;

    peripherals.push_back(&flash);

    // Bus state: iterate along table
    auto state = states.begin();
    cpu_cycle cycle = T1;

    // "reset" the CPU
    tb->IORQ = tb->RD = tb->WR = tb->M1 = 1;

    // /WAIT is latched at the start of T2/TW
    bool latched_wait = false;

    vluint8_t waited = 0;

    // Tick the clock until we are done
    while(state < states.end()) {
        bool phi_clocked = false;

        // Let any combinatorial changes from the CPU settle
        // Verilator doesn't handle tri-state logic
        tb->eval();

        double next_phi = phi_ticks/(PHI_FREQ*2);
        double next_osc = osc_ticks/(OSC_FREQ*2);
        if (next_phi < next_osc) {
            elapsed = next_phi;
            phi_ticks++;
            tick = 1e6*elapsed;
            phi_state = 1 - phi_state;
            tb->i_phi = phi_state;
            phi_clocked = true;
        } else {
            elapsed = next_osc;
            osc_ticks++;
            tick = 1e6*elapsed;
            osc_state = 1 - osc_state;
            tb->i_clk = osc_state;
        }

        if (tfp) tfp->dump(tick - 1);
        tb->eval();

        for (peripheral *p : peripherals) {
            p->eval(tb, elapsed);
        }

        // check for edges on signals of interest

        if (phi_clocked) {
            switch (cycle) {
                case T1:
                    if (phi_state) {
                        tb->i_addr = state->address;
                    }
                    // check for falling edge
                    if (!phi_state) {
                        // T1 falls: /IORQ low, /RD low for reads, data to <byte> for writes
                        tb->IORQ = 0;
                        if (state->op == IORead) tb->RD = 0;
                        if (state->op == IOWrite) {
                            tb->i_data = state->byte;
                            cout << setw(70) << setfill('.') << left << state->desc << success << endl;
                        }
                        cycle = T2;
                    }
                    break;
                case T2:
                    // T2 rises: /WR low for writes
                    if (phi_state && state->op == IOWrite) {
                        tb->WR = 0;
                    }
                    if (phi_state) latched_wait = tb->waitstate;
                    if (!phi_state) {
                        cycle = TW;
                        wait_cycles = 1;
                    }
                    break;
                case TW:
                    if (phi_state) latched_wait = tb->waitstate;
                    // TW falls: sample /WAIT
                    if (!phi_state) {
                        if (latched_wait || wait_cycles < MIN_WAITS) {
                            wait_cycles++;
                            if (wait_cycles > 20) {
                                cout << "ERROR: More than 20 wait cycles elapsed." << endl;
                                state = states.end();
                            }
                        } else {
                            cycle = T3;
                        }
                    }
                    break;
                case T3:
                    if (!phi_state) {
                        // T3 falls: latch data for reads, /IORQ, /RD, /WR go high, data goes high
                        if (state->op == IORead) {
                            cout << setw(70) << setfill('.') << left << state->desc;
                            vluint8_t output = tb->o_data_en ? tb->o_data : 0xff;
                            if (output != state->byte) {
                                // Set up numbers as base-16, 0-padded, right-aligned
                                cout << hex << setfill('0') << right;
                                cout << failure << " (was: 0x" << setw(2) << (unsigned)output << ", expected: 0x";
                                cout << setw(2) << (unsigned)state->byte << ")";
                            } else {
                                cout << success;
                            }
                            cout << endl;
                        }

                        if (state->op == Cycle && (++waited) < state->byte) {
                        } else {
                            state++;
                            waited = 0;
                        }
                        cycle = T1;
                        tb->IORQ = tb->RD = tb->WR = 1;
                    }
                    break;
            }
        }

        if (tfp) tfp->dump(tick);
        if (tfp) tfp->flush();
    }

    tfp->close();

    exit(EXIT_SUCCESS);
}
