#ifndef SPI_FLASH_H
#define SPI_FLASH_H

#include "Vfpga20.h"
#include "peripheral.h"

class spiflash : public peripheral {
private:
    enum state { Idle, Shift, Latch };
    state state;
    uint8_t command;
    uint32_t address;
    uint8_t xmit_byte;
    bool is_xmit;
    uint8_t recv_byte;
    uint8_t bit;
public:
    spiflash();
    void eval(Vfpga20 *module, double time);
private:
    void execute();
};

#endif
