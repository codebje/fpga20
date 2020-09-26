# TRS-20 CPU board FPGA

The FPGA on the TRS-20's CPU board serves several roles:

  - User LED control
  - I2C master for off-board peripherals
  - SPI master to read or program the W25Q ROM (FPGA bitstreams)
  - Interrupt controller for off-board peripherals
  - General FPGA playground for unspecified future use

## Module guide

  - [fpga20.v](src/fpga20.v): the top-level module, wiring other modules to exernal pins
  - [i2c.v](src/i2c.v): the I2C master module
  - [leds.v](src/leds.v): LED control module
  - [spi_master.v](src/spi_master.v): SPI master module
  - [int.v](src/int.v): Interrupt controller module

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

## SPI master

  - BUSY bit in status register for program/erase operations
  - Write-enable latch (WEL) read-only bit in status register
  - BP2, BP1, BP0 block-protect R/W bits in status register (default 0, nothing protected)
  - TB top/bottom protect R/W bit determines if BP\* protect from top down or bottom up
  - SEC R/W bit controls whether BP\* protects 4kb sectors or 64kb blocks
  - CMP R/W bit complements protection of SEC, TB, BP2, BP1, BP0
  - Can protect first 32kB with CMP=0, SEC=1, TB=1, BP2=1, BP1=0, BP0=X
  - MSB first

## Interrupt controller

Not yet implemented.

## User LED control

Port 0x0100 may be used to control the two user LEDs.

| Bit | Name | Purpose                                                                          |
| --- | ---- | -------------------------------------------------------------------------------- |
|  0  | LED0 | State of User LED 1. Set for ON, reset for OFF.                                  |
|  1  | LED1 | State of User LED 2. Set for ON, reset for OFF.                                  |
|  2  | CLK0 | Blinks LED0 from 100MHz external oscillator if set.                              |
|  3  | CLK1 | Blinks LED1 from CPU clock signal if set.                                        |
|  4  | RES0 | Reserved.                                                                        |
|  5  | RES1 | Reserved.                                                                        |
|  6  | RES2 | Reserved.                                                                        |
|  7  | RES3 | Reserved.                                                                        |

If CLK0 is set, LED0 will oscillate at approx. 1.49Hz, switching User LED 1 on and off. CLK1 controls LED1 and User LED 2 at PHI/2^24, which is approx. 1.1Hz at 18.432MHz. The remaining four bits are reserved for future use.

## CPU interface

| Port  | Description                                                                           |
| ----- | ------------------------------------------------------------------------------------- |
| 0100  | Write: User LEDs, status control                                                      |
|       | Read: FPGA status information                                                         |
| 0101  | Interrupt controller diddly-dee                                                       |
| 0102  | Interrupt controller diddly-dee                                                       |
| 0103  | Interrupt controller diddly-dee                                                       |
| 0104  | I2C something-or-other                                                                |
| 0105  | I2C something-or-other                                                                |
| 0106  | I2C something-or-other                                                                |
| 0107  | I2C something-or-other                                                                |
| 0108  | SPI something-or-other                                                                |
| 0109  | SPI something-or-other                                                                |
| 010A  | SPI something-or-other                                                                |
| 010B  | SPI something-or-other                                                                |

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

