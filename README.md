![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Full-Duplex 8N1 UART Transceiver

A robust, full-duplex 8N1 (8 data bits, no parity, 1 stop bit) Universal Asynchronous Receiver-Transmitter (UART) peripheral designed for silicon tapeout on the **IHP SG13G2 130nm BiCMOS** open-source PDK via **Tiny Tapeout (TTIHP26b)**.

- **Author:** NUAT Labs
- **License:** Apache 2.0
- **Target Shuttle:** TTIHP26b (IHP 130nm SG13G2)
- **Top Module:** `tt_um_nuatlabs_uart`
- **Tile Allocation:** 1x1 Standard Tile (~167 µm x 108 µm)
- **Datasheet:** [docs/info.md](docs/info.md)

---

## Block Diagram

```
                              +---------------------------------------------+
                              |             tt_um_nuatlabs_uart             |
                              |                                             |
   ui_in[0] (rxd) ----------->|--> [2-Stage Synchronizer]                   |
                              |               |                             |
                              |               v                             |
                              |       [UART RX (8N1)]                       |
                              |       - Mid-bit sampling (BAUD_DIV/2)       |
                              |       - Stop-bit verification               |
                              |               |                             |
                              |         rx_data[7:0]                        |
                              |               |                             |
                              |               +---------------------------->|--> uo_out[2] (rx_valid)
                              |                                             |
   ui_in[1] (tx_start) ------>|-----> [UART TX (8N1)]                       |
                              |       - Moore FSM                           |
                              |       - Serial framing (Start/Data/Stop)    |
                              |               |                             |
                              |               +---------------------------->|--> uo_out[0] (txd)
                              |               +---------------------------->|--> uo_out[1] (tx_busy)
                              |                                             |
                              |   +-------------------------------------+   |
   ui_in[2] ----------------->|-->| Bus Multiplexer & Direction Control |   |
   (uio_load_mode)            |   +-------------------------------------+   |
                              |           |                         ^       |
                              |     tx_data_bus                rx_data_bus  |
                              |           |                         |       |
                              +-----------|-------------------------|-------+
                                          v                         |
                                  uio[7:0] (Input)           uio[7:0] (Output)
                                  when load_mode=1           when load_mode=0
```

---

## Features

- **Full-Duplex Architecture**: Independent transmitter and receiver state machines capable of simultaneous transmission and reception.
- **Noise-Immune Reception**:
  - Two-stage flip-flop synchronizer on the asynchronous serial line (`rxd`) prevents metastability issues.
  - Mid-bit oversampling (`BAUD_DIV / 2`) guarantees maximum noise margin and tolerance to clock skew.
  - Single-cycle registered `rx_valid` pulse and latched `rx_data` output.
- **Glitch-Free Transmission**:
  - 3-block Moore FSM with distinct start, data, and stop states.
  - Active-high `tx_busy` status output provides clear handshaking to host controllers.
- **Dynamic Bus Multiplexing**:
  - Standard Tiny Tapeout tiles provide 8 bidirectional IO pins (`uio`).
  - Runtime mode pin `uio_load_mode` dynamically configures `uio[7:0]` as parallel input (load byte to transmit) or parallel output (read received byte), enabling full 8-bit parallel transfers without pin-starvation.
- **Parameterized Baud Rate Generator**:
  - Controlled by parameter `BAUD_DIV = f_clk / baud_rate`.
  - Defaulted to `4` for fast, cycle-accurate simulation and verification.

---

## Pinout Specification

### Dedicated Inputs (`ui_in`)

| Pin | Name | Description |
|---|---|---|
| `ui_in[0]` | `rxd` | Asynchronous serial input line (idles high) |
| `ui_in[1]` | `tx_start` | Active-high pulse (1 cycle) to initiate byte transmission |
| `ui_in[2]` | `uio_load_mode` | Bus mode: `1` = `uio` is input (`tx_data`), `0` = `uio` is output (`rx_data`) |
| `ui_in[7:3]` | Reserved | Tied off internally |

### Dedicated Outputs (`uo_out`)

| Pin | Name | Description |
|---|---|---|
| `uo_out[0]` | `txd` | Serial output line (idles high, active low start bit) |
| `uo_out[1]` | `tx_busy` | Active-high status flag indicating transmission in progress |
| `uo_out[2]` | `rx_valid` | Active-high 1-cycle pulse asserting valid byte reception |
| `uo_out[7:3]` | Reserved | Driven low (`0`) |

### Bidirectional IOs (`uio[7:0]`)

| Pin | Mode (`load_mode = 1`) | Mode (`load_mode = 0`) |
|---|---|---|
| `uio[0]` | `tx_data[0]` (Input LSB) | `rx_data[0]` (Output LSB) |
| `uio[1]` | `tx_data[1]` (Input) | `rx_data[1]` (Output) |
| `uio[2]` | `tx_data[2]` (Input) | `rx_data[2]` (Output) |
| `uio[3]` | `tx_data[3]` (Input) | `rx_data[3]` (Output) |
| `uio[4]` | `tx_data[4]` (Input) | `rx_data[4]` (Output) |
| `uio[5]` | `tx_data[5]` (Input) | `rx_data[5]` (Output) |
| `uio[6]` | `tx_data[6]` (Input) | `rx_data[6]` (Output) |
| `uio[7]` | `tx_data[7]` (Input MSB) | `rx_data[7]` (Output MSB) |

---

## Baud Rate & Clocking Math

The relationship between the system clock frequency and target baud rate is:

$$\text{BAUD\_DIV} = \left\lfloor \frac{f_{\text{clk}}}{\text{Baud Rate}} \right\rfloor$$

| Clock Frequency ($f_{\text{clk}}$) | Target Baud Rate | Ideal `BAUD_DIV` | Actual Baud Rate | Error (%) |
|---|---|---|---|---|
| 50 MHz | 115,200 | 434 | 115,207 | +0.006% |
| 50 MHz | 921,600 | 54 | 925,925 | +0.47% |
| 10 MHz | 115,200 | 87 | 114,942 | -0.22% |
| 10 MHz | 9,600 | 1042 | 9,596.9 | -0.03% |
| Simulation | Fast Test | 4 | $f_{\text{clk}} / 4$ | 0.00% |

---

## Verification & Simulation

The testbench is built using [Cocotb](https://www.cocotb.org/) and Icarus Verilog (`iverilog`).

### Prerequisites
- Python 3.10+
- Icarus Verilog (`iverilog`, `vvp`)

### Running the Test Suite
```bash
# Set up virtual environment
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r test/requirements.txt

# Run simulation
cd test
make clean
make SIM=icarus
```

### Test Suite Coverage
1. **`test_uart_tx_shape`**: Verifies exact serial waveform timings, including start bit (0), 8 data bits (LSB-first), stop bit (1), and active interval of `tx_busy`.
2. **`test_uart_loopback_single_byte`**: Full external wire loopback test dynamically coupling `uo_out[0]` (`txd`) to `ui_in[0]` (`rxd`), validating reception, stop-bit validation, and `rx_data` latching.
3. **`test_uart_loopback_multiple_bytes`**: Consecutive multi-byte stress tests with boundary patterns (`0x00`, `0xFF`, `0x55`, `0xAA`, `0x81`, `0x7E`).

---

## Repository Structure

```
.
├── .github/workflows/   # Tiny Tapeout CI Actions (gds, test, docs, fpga)
├── docs/
│   └── info.md          # Technical datasheet for Tiny Tapeout catalog
├── src/
│   ├── config.json      # LibreLane ASIC hardening configuration
│   ├── project.v        # Top-level module (tt_um_nuatlabs_uart)
│   ├── uart_tx.v        # 8N1 UART transmitter with Moore FSM
│   └── uart_rx.v        # 8N1 UART receiver with 2-stage synchronizer
├── test/
│   ├── Makefile         # Cocotb simulator makefile
│   ├── requirements.txt # Python dependencies (cocotb, pytest)
│   ├── tb.v             # Verilog testbench wrapper
│   └── test.py          # Cocotb test cases
├── info.yaml            # Tiny Tapeout chip submission metadata & pinout
└── README.md            # Project documentation & branding
```

---

## About NUAT Labs

**NUAT Labs** designs open-source silicon and digital hardware IP tailored for rapid tapeout on open PDKs.
