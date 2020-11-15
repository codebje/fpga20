# TRS-20 CPU board FPGA

The FPGA on the TRS-20's CPU board serves several roles:

  - User LED control
  - I2C master for off-board peripherals
  - SPI master to read or program the W25Q ROM (FPGA bitstreams)
  - Interrupt controller for off-board peripherals
  - General FPGA playground for unspecified future use

## Current status

  - [x] Automated testing
  - [ ] Automated verification
  - [ ] Tested on iCEstick
  - [x] Deployed to CPU board
  - [x] SPI access to Flash
  - [x] ... including writes
  - [ ] I2C master
  - [x] Warm boot controller
  - [ ] Interrupt controller

  - LUTs used: 190/1280 (14%)
  - RAM blocks used: 0/16 (0%)
  - Max. frequency for CLK1: 160.49MHz
  - Max. frequency for PHI: 190.33MHz

## Module guide

  - [toplevel.v](src/toplevel.v): the top-level module, wiring other modules to exernal pins
  - [fpga20.v](src/fpga20.v): interface to the Z180 bus, plus the SPI master
  - [i2c.v](src/i2c.v): the I2C master module - TODO
  - [leds.v](src/leds.v): LED blinker
  - [int.v](src/int.v): Interrupt controller module - TODO

## CPU interface

| Port  | Description                                                                           |
| ----- | ------------------------------------------------------------------------------------- |
| 0100  | Status/Control                                                                        |
| 0101  | Version information                                                                   |
| 0104  | SPI data                                                                              |

## Status/Control port

Port 0100 sets or reports the status of the FPGA system controller.

| Bit |  Name  | Purpose                                                                        |
| --- | ------ | ------------------------------------------------------------------------------ |
|  0  | LED0   | State of User LED 1. Set for ON, reset for OFF.                                |
|  1  | LED1   | State of User LED 2. Set for ON, reset for OFF.                                |
|  2  | CLK0   | Blinks LED0 from 100MHz external oscillator if set.                            |
|  3  | CLK1   | Blinks LED1 from CPU clock signal if set.                                      |
|  4  | SPI    | Indicates an SPI transaction is active.                                        |
|  5  | S0     | Warm boot selector S0.                                                         |
|  6  | S1     | Warm boot selector S1.                                                         |
|  7  | WBOOT  | Warm boot trigger.                                                             |

If CLK0 is set, LED0 will oscillate at approx. 1.49Hz, switching User LED 1 on and off. CLK1 controls LED1 and User LED 2 at PHI/2^24, which is approx. 1.1Hz at 18.432MHz. If CLK0/CLK1 is set, the values in LED0/LED1 have no effect.

The SPI bit must be written high to begin a transaction with the Flash IC. While it is high, the Flash's chip select line will be active. A write to the SPI data I/O port will transmit a byte to the Flash IC, while a read from the I/O port will read a byte. During a read, MOSI is held high to prevent an incorrect read resulting in unpredictable data being sent to the device.

When WBOOT is written high, the FPGA will reboot using the image selected by `{ S0, S1 }`.

## SPI master

The SPI master controls only the SPI flash attached to the FPGA. The slave select line is controlled by the `SPI` bit of the Status/Control port - unless this bit is high, all other SPI actions will have no effect. Once this bit has been set high, an SPI flash command byte should be written to the SPI data port. Command bytes that would trigger dual or quad I/O modes will cause the `SPI` bit to be reset, but all other bytes including invalid commands will be sent to the flash.

No protection is given for reading before writing (the flash ROM will receive a command byte of 0xff), writing when the flash expects to be responding (the response data will be lost), or reading when the flash expects to be given data (the flash will get 0xff, which probably won't be right). Both reads and writes complete during the requesting CPU cycle, with reads using `/WAIT` to insert a second wait state if the CPU is only inserting one.

After a transaction is complete the `SPI` bit should be reset to raise slave select and indicate to the flash that the transaction is over.

### ROM image map

A bitstream for the iCE40HX1K is 32,220 bytes in size.  The iCE40 can handle four distinct bitstreams in the ROM data, selected by two pins in cold boot mode or by software in warm boot mode. To ease in-system programming the bitstreams are aligned to 32kb addresses. This allows W25Q block-erase operations to erase and replace one entire bitstream. The ROM after 0x20000 is free for currently unspecified uses.

| From   | To     | Purpose                                                                     |
| ------ | ------ | --------------------------------------------------------------------------- |
| 000000 | 00009F | Bitstream preamble. Do not overwrite except with an identical preamble.     |
| 0000A0 | 007FFF | Bitstream 1. This is the recovery bitstream and should not be overwritten.  |
| 008000 | 00FFFF | Bitstream 2. This is the default boot bitstream.                            |
| 010000 | 017FFF | Bitstream 3. Reserved for future use.                                       |
| 018000 | 01FFFF | Bitstream 4. Reserved for future use.                                       |
| 020000 | 400000 | Free for non-volatile storage.                                              |

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

# Decision log

### 04/10/2020 SPI master: prevent dual and quad mode I/O

The original design was to provide an enable bit more or less directly tied to the slave select pin, and to then use a data port to read and write bytes. This design works, and with a 50MHz SPI clock speed one extra wait state is required for reads but not for writes. Dual-mode reads and writes do not need extra wait states. This works, as of revision a715b8e.

However, it's not very safe. A dual-mode write uses both the MOSI and MISO pins as inputs to the flash IC, and a dual-mode read uses them both as outputs from the flash IC. If the master and slave aren't perfectly synchronised on which direction data is going at all times then they will try to drive these lines in opposition to each other. This will likely result in one or both of them getting a fried pin. This would happen if the flash IC expects to output data when the CPU attempts to also output data - either single or dual mode.

To resolve this, the current release instead forces single mode I/O. Any dual or quad I/O command is filtered in the FPGA; the worst the CPU can do now is erase the flash and force me to remove and reprogram the IC off-board. This is cheap and easy, the IC is socketed for just such a purpose.

### 05/10/2020 SPI master: don't use separate module

The current SPI master code is not in a separate module. There's a lot of intimate sharing of knowledge between the SPI pathways and the Z180 bus pathways. It would be possible to separate these out, but doing so would require a ton of boilerplate to wire stuff back up together - or extra wait states. Since it's so ridiculously simple, I've chosen to just leave it in the main module.

Adding the warmboot control in exposed that the test harness doesn't like `SB_WARMBOOT`, unsurprisingly. Splitting out a toplevel to wire up FPGA pins to internal signals resolves this, and invites more work to move the tristate logic out to the toplevel too. This simplifies the test harness.

### 10/10/2020 Change the `o_data_en` signal

One of the slowest portions of the logic at present is testing whether the read register should be active or not. This is because a set of port values are tested - 0100, 0101, and 0104. It's also potentially got metastability problems - the `io_read` register value is stabilised but the address lines are not. `io_read` may remain asserted up to 20ns after the CPU has de-asserted `/IORQ` and `/RD`, but the address line are only guaranteed to hold their values for 5ns. It's not terribly critical if it's indeterminate whether the FPGA continues to assert data for half a clock cycle or not, but it is critical if the FPGA decides it needs to assert data during some other peripheral's I/O read because the address lines change in the 15ns of uncertainty, while the other peripheral is also asserting data.

### 10/10/2020 Change the `waitstate` signal

`/WR` falls after the rising edge of T2 - up to 25ns after. However, `/WAIT` needs to be set before the rising edge of the following Tw for the '1g175 to pass it through to the CPU for the falling edge of Tw. The current approach is to set `/WAIT` using a synchronised rising edge of `PHI`. This must use T2 to be set in time for Tw, but this edge is detected after 10 to 20ns. A first pass fix can catch a `/WR` fall that stabilises in the same 100MHz clock edge as T2's rise, but a redesign is required.

Using `always @(posedge PHI)` is too late - `/WR` will not fall until some time between the rise of T2 and 25ns after that, so the next positive edge is Tw. `/WAIT` must be set by then for the '1g175 to clock it in.
