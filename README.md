# TRS-20 CPU board FPGA

The FPGA on the TRS-20's CPU board serves several roles:

  - User LED control
  - I2C master for off-board peripherals
  - SPI master to read or program the W25Q ROM (FPGA bitstreams)
  - Interrupt controller for off-board peripherals
  - General FPGA playground for unspecified future use

## Module guide

  - [fpga20.v](src/fpga20.v): the top-level module, wiring other modules to exernal pins
  - [spi_master.v](src/spi_master.v): SPI master module
  - [i2c.v](src/i2c.v): the I2C master module - TODO
  - [leds.v](src/leds.v): LED control module - TODO
  - [int.v](src/int.v): Interrupt controller module - TODO

## SPI master

The original design was to provide an enable bit more or less directly tied to the slave select pin, and to then use a data port to read and write bytes. This design works, and with a 50MHz SPI clock speed one extra wait state is required for reads but not for writes. Dual-mode reads and writes do not need extra wait states. This works, as of revision a715b8e.

However, it's not very safe. A dual-mode write uses both the MOSI and MISO pins as inputs to the flash IC, and a dual-mode read uses them both as outputs from the flash IC. If the master and slave aren't perfectly synchronised on which direction data is going at all times then they will try to drive these lines in opposition to each other. This will likely result in one or both of them getting a fried pin. This would happen if the flash IC expects to output data when the CPU attempts to also output data - either single or dual mode.

To resolve this, the current release instead forces single mode I/O. Any dual or quad I/O command is filtered in the FPGA; the worst the CPU can do now is erase the flash and force me to remove and reprogram the IC off-board. This is cheap and easy, the IC is socketed for just such a purpose.

## I2C master

Not yet implemented.

  - One port to set slave address and r/w bit on write, status on read.
  - One port for data in/out.
  - Clock at PHI/2^6, or 281.25kHz at 18.432MHz (maybe let configure up to 2^8, 70.3125kHz)
  - 64 cycles per I2C cycle, min. 576 cycles per byte transmitted
  - Single master can hold bus indefinitely though SMBus slaves will time out after 35ms
  - Clock stretching probably best to permit especially at 280kHz
  - Should also use interrupt controller to signal rx/tx done to CPU
  - Repeated ops driven by something out of:
      - Byte count set at start
      - Read/write ops on I/O port before last op done (/WAIT perhaps)
      - Timing sensitive requirement to read/write within 35ms of last op
      - Keep reading/writing until told explicitly to stop (until FIFOs fill/empty, that is)

## Interrupt controller

Not yet implemented.

## Status 1

Port 0100 sets or reports the status of the FPGA system controller.

| Bit |  Name  | Purpose                                                                        |
| --- | ------ | ------------------------------------------------------------------------------ |
|  0  | LED0   | State of User LED 1. Set for ON, reset for OFF.                                |
|  1  | LED1   | State of User LED 2. Set for ON, reset for OFF.                                |
|  2  | CLK0   | Blinks LED0 from 100MHz external oscillator if set.                            |
|  3  | CLK1   | Blinks LED1 from CPU clock signal if set.                                      |
|  4  | SPI    | Indicates an SPI transaction is active.                                        |
|  5  | -      | Reserved.                                                                      |
|  6  | -      | Reserved.                                                                      |
|  7  | -      | Reserved.                                                                      |

If CLK0 is set, LED0 will oscillate at approx. 1.49Hz, switching User LED 1 on and off. CLK1 controls LED1 and User LED 2 at PHI/2^24, which is approx. 1.1Hz at 18.432MHz. If CLK0/CLK1 is set, the values in LED0/LED1 have no effect.

The SPI bit must be written high to begin a transaction with the Flash IC. While it is high, the Flash's chip select line will be active. A write to the SPI data I/O port will transmit a byte to the Flash IC, while a read from the I/O port will read a byte. During a read, MOSI is 

## CPU interface

| Port  | Description                                                                           |
| ----- | ------------------------------------------------------------------------------------- |
| 0100  | Status control                                                                        |
| 0104  | SPI data                                                                              |

## ROM image map

A bitstream for the iCE40HX1K is 32,220 bytes in size.  The iCE40 can handle four distinct bitstreams in the ROM data, selected by two pins in cold boot mode or by software in warm boot mode. To ease in-system programming the bitstreams are aligned to 32kb addresses. This allows W25Q block-erase operations to erase and replace one entire bitstream. The ROM after 0x20000 is free for currently unspecified uses.

| From   | To     | Purpose                                                                     |
| ------ | ------ | --------------------------------------------------------------------------- |
| 000000 | 00009F | Bitstream preamble. Do not overwrite except with an identical preamble.     |
| 0000A0 | 007FFF | Bitstream 1. This is the recovery bitstream and should not be overwritten.  |
| 008000 | 00FFFF | Bitstream 2. This is the default boot bitstream.                            |
| 010000 | 017FFF | Bitstream 3. Reserved for future use.                                       |
| 018000 | 01FFFF | Bitstream 4. Reserved for future use.                                       |
| 020000 | 400000 | Free for non-volatile storage.                                              |

## Decision log

### 04/10/2020 SPI master: prevent dual and quad mode I/O
