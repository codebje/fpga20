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
    switch (state) {
        case Idle:
            if (!module->SPI_SS) {
                // Mode 0: SCK is already low, get first bit onto MISO
                // Mode 3: SCK is high, shift when it falls
                state = module->SPI_SCK ? Shift : Latch;
                if (state == Shift) {
                    module->SPI_SDI = (xmit_byte >> 7) & 1;
                    xmit_byte <<= 1;
                }
            }
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
            module->SPI_SDI = (xmit_byte >> 7) & 1;
            xmit_byte <<= 1;
            break;
    }
}

void spiflash::execute() {
    printf("spi received byte %02x", recv_byte);
}
