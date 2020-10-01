#include "spiflash.h"

#include <iostream>

// FSM:
//  Idle: wait for SS low
//  Transfer: latch on rising edge of SCK
//            shift on falling edge

spiflash::spiflash() {
    state = Idle;
    xmit_byte = 0;
    is_xmit = false;
    is_dual = false;
    recv_byte = 0;
    bit = 0;
}

// true if the flash is driving SDI/SDO at the same time as the FPGA
bool spiflash::line_conflicts(Vfpga20 *module) {
    if (is_xmit && module->fpga20__DOT__spi_sdi_en) return true;
    if (is_xmit && is_dual && module->fpga20__DOT__spi_sdo_en) return true;
    return false;
}

void spiflash::eval(Vfpga20 *module, double time) {
    // if the flash is not selected, reset state and bail out
    if (module->SPI_SS) {
        state = Idle;
        command = 0;
        address = 0;
        return;
    }

    switch (state) {
        case Idle:
            // Mode 0: SCK is already low, get first bit onto MISO
            // Mode 3: SCK is high, shift when it falls
            state = module->SPI_SCK ? Shift : Latch;
            if (state == Shift) {
                if (is_xmit) {
                    module->SPI_SDI = (xmit_byte >> 7) & 1;
                    xmit_byte <<= 1;
                    if (is_dual) {
                        module->SPI_SDO = (xmit_byte >> 7) & 1;
                        xmit_byte <<= 1;
                    }
                }
            }
            break;
        // in the Shift state wait for SCK high, then latch
        case Shift:
            if (module->SPI_SCK) {
                if (!is_xmit) {
                    recv_byte = (recv_byte << 1) | (module->SPI_SDO & 1);
                    if (is_dual) {
                        recv_byte = (recv_byte << 1) | (module->SPI_SDI & 1);
                    }
                }
                bit = bit + (is_dual ? 2 : 1);
                if (bit == 8) {
                    bit = 0;
                    execute();
                }
                state = Latch;
            }
            break;
        // in the Latch state wait for SCK low, then shift
        case Latch:
            if (!module->SPI_SCK) {
                if (is_xmit) module->SPI_SDI = (xmit_byte >> 7) & 1;
                xmit_byte <<= 1;
                if (is_xmit && is_dual) {
                    module->SPI_SDO = (xmit_byte >> 7) & 1;
                    xmit_byte <<= 1;
                }
                state = Shift;
            }
            break;
    }
}

void spiflash::execute() {
    printf("spi received byte %02x (command=%02x, is_xmit=%d, address=%d)\n", recv_byte, command, is_xmit, address);
    if (command == 0) {
        switch (recv_byte) {
            case 0x90:
                command = 0x90;
                address = 0;
                is_xmit = is_dual = false;
                break;
            case 0x92:
                command = 0x92;
                address = 0;
                is_xmit = false;
                is_dual = true;
                break;
            default:
                is_xmit = is_dual = false;
                break;
        }
    } else {
        switch (command) {
            case 0x90:
            case 0x92:
                address++;
                switch (address) {
                    case 4:
                        is_xmit = true;
                        xmit_byte = 0xef;
                        break;
                    case 5:
                        is_xmit = true;
                        xmit_byte = 0x15;
                        break;
                    default:
                        xmit_byte = 0;
                        is_xmit = false;
                        break;
                }
                break;
            default:
                printf("bogus SPI command %02x\n", command);
                is_xmit = false;
                break;
        }
    }
}
