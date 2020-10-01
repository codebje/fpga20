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

  - BUSY bit in status register for program/erase operations
  - Write-enable latch (WEL) read-only bit in status register
  - BP2, BP1, BP0 block-protect R/W bits in status register (default 0, nothing protected)
  - TB top/bottom protect R/W bit determines if BP\* protect from top down or bottom up
  - SEC R/W bit controls whether BP\* protects 4kb sectors or 64kb blocks
  - CMP R/W bit complements protection of SEC, TB, BP2, BP1, BP0
  - Can protect first 32kB with CMP=0, SEC=1, TB=1, BP2=1, BP1=0, BP0=X
  - MSB first

The Status A port (0100) is used for SPI control. The SPI Data port (0104) is used for data in/out.

Writing to the data port will store a byte in the output buffer and set the output buffer as full. Reading from the data port will read the last byte received from the slave and set the input buffer as empty. When the output buffer is full and the input buffer is empty the SPI clock will send eight pulses to transfer a byte each direction. If the output buffer is written before the byte has been fully transmitted, data corruption may occur.

The SPI clock runs off the 100MHz oscillator. It takes eight cycles to transfer a byte, 80ns; this will happen between 1.47 and 1.66 PHI cycles later. Adding an extra cycle for metastability reaches up to 1.84 PHI cycles, less than 10ns before the 2nd clock rise.

/WR will be low for at least 150ns for an IO cycle, with data valid at least 10ns before and after that event. Latching /WR and /IORQ via a stabilizer chain will give more than enough time to transmit 8 bits over SPI at 100MHz before the end of the write cycle. However /RD only has ~90ns available before data must be on the data bus, which is not enough time to run a full SPI transfer including stabilizers and up to 10ns to observe /RD's falling edge. Using a write or read to initiate a transfer, with a read retrieving the _last_ transferred value, is well within timing constraints.

One port for single-mode read/write, with /WAIT held low while the operation is in progress. One port for dual-mode read/write, with /WAIT held low while the operation is in progress. The W32Q never reads and writes at the same time.

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
|  5  | SPITX  | Set when the SPI transmit buffer is full.                                      |
|  6  | SPIRX  | Set when the SPI receive buffer is full.                                       |
|  7  | SPIDIR | Set to drive SPI by the receiver buffer, reset to drive by the transmit buffer |

If CLK0 is set, LED0 will oscillate at approx. 1.49Hz, switching User LED 1 on and off. CLK1 controls LED1 and User LED 2 at PHI/2^24, which is approx. 1.1Hz at 18.432MHz. If CLK0/CLK1 is set, the values in LED0/LED1 have no effect.

The SPI bit must be set while a transaction is in progress. While the bit is set the SPI slave select line will be active and transmission will be enabled.

The SPITX and SPIRX bits are read-only. SPITX is set when a byte has been received from the processor on the SPI data port but not yet transmitted to the SPI slave. SPIRX is set when a byte has been received from the SPI slave but not yet consumed by the processor. If SPIDIR is reset (the default) then a transmission will begin when SPITX is set - that is, writing the next byte to the data port will automatically send the byte. This transmission will overwrite whatever was in the receive buffer, which must be read prior to writing if its contents are important. If SPIDIR is set then a transmission will begin when SPIRX is clear - that is, reading a byte from the data port will begin reading the next byte.


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

