#include "spiflash.h"

#include <iostream>

// FSM:
//  Idle: wait for SS low
//  Transfer: latch on rising edge of SCK
//            shift on falling edge

spiflash::spiflash() {
    state = Idle;
    xmit_byte = 0;
    recv_byte = 0;
    bit = 0;
}

void spiflash::eval(Vfpga20 *module, double time) {
    // if the flash is not selected, reset state and bail out
    if (module->SPI_SS) {
        module->SPI_SDI = 1;    // internal pull-up on the FPGA
        state = Idle;
        command = 0;
        address = 0;
        return;
    }

    switch (state) {
        case Idle:
            // Mode 0: SCK is already low, get first bit onto MISO
            // Mode 3: SCK is high, shift when it falls
            state = module->SPI_SCK ? Latch : Shift;
            break;
        // in the Shift state wait for SCK high, then latch
        case Shift:
            if (module->SPI_SCK) {
                recv_byte = (recv_byte << 1) | (module->SPI_SDO & 1);
                if (++bit == 8) {
                    bit = 0;
                    execute();
                }
                state = Latch;
            }
            break;
        // in the Latch state wait for SCK low, then shift
        case Latch:
            if (!module->SPI_SCK) {
                module->SPI_SDI = (xmit_byte >> 7) & 1;
                xmit_byte <<= 1;
                state = Shift;
            }
            break;
    }
}

void spiflash::execute() {
    if (command == 0) {
        switch (recv_byte) {
            case 0x90:
                command = 0x90;
                address = 0;
                xmit_byte = 0xff;
                break;
            default:
                break;
        }
    } else {
        switch (command) {
            case 0x90:
            case 0x92:
                address++;
                switch (address) {
                    case 4:
                        xmit_byte = 0xef;
                        break;
                    case 5:
                        xmit_byte = 0x15;
                        break;
                    default:
                        xmit_byte = 0xff;
                        break;
                }
                break;
            default:
                printf("bogus SPI command %02x\n", command);
                break;
        }
    }
}
