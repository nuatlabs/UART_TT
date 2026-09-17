/*
 * Copyright (c) 2026 NUAT Labs
 * SPDX-License-Identifier: Apache-2.0
 *
 * tt_um_nuatlabs_uart
 * -------------------
 * Full-duplex 8N1 UART Transceiver (TX + RX) for Tiny Tapeout.
 * Features an 8-bit time-multiplexed bidirectional data bus (uio)
 * with dedicated status and serial lines.
 *
 * Pinout
 * ------
 * ui_in[0] : rxd              (external serial data in)
 * ui_in[1] : tx_start (pulse) (latch uio_in as tx_data and begin sending)
 * ui_in[2] : uio_load_mode    (1 = uio is an INPUT carrying the byte to transmit;
 *                              0 = uio is an OUTPUT showing the last received byte)
 * ui_in[7:3] : unused (reserved)
 *
 * uo_out[0] : txd             (external serial data out)
 * uo_out[1] : tx_busy         (high while transmitting)
 * uo_out[2] : rx_valid        (1-cycle pulse when byte reception is complete)
 * uo_out[7:3] : unused (driven low)
 *
 * uio[7:0] : tx_data (input, when uio_load_mode=1) /
 *            rx_data (output, when uio_load_mode=0) -- time-multiplexed
 *            bidirectional bus with direction dynamically controlled.
 *
 * Baud Rate:
 * BAUD_DIV = clk_hz / desired_baud. Defaulted to 4 for fast, deterministic
 * simulation in cocotb.
 */
`default_nettype none

module tt_um_nuatlabs_uart (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  wire       rxd            = ui_in[0];
  wire       tx_start       = ui_in[1];
  wire       uio_load_mode  = ui_in[2];

  wire [7:0] tx_data_bus    = uio_in;  // valid when uio_load_mode = 1

  wire       txd;
  wire       tx_busy;
  wire [7:0] rx_data;
  wire       rx_valid;

  // ---------------- Transmitter Instance ----------------
  uart_tx #(
      .BAUD_DIV(4)   // small divisor for fast, deterministic cocotb sims
  ) u_tx (
      .clk      (clk),
      .rst_n    (rst_n),
      .tx_start (tx_start),
      .tx_data  (tx_data_bus),
      .txd      (txd),
      .tx_busy  (tx_busy)
  );

  // ---------------- Receiver Instance ----------------
  uart_rx #(
      .BAUD_DIV(4)
  ) u_rx (
      .clk      (clk),
      .rst_n    (rst_n),
      .rxd      (rxd),
      .rx_data  (rx_data),
      .rx_valid (rx_valid)
  );

  // Dedicated outputs mapping
  assign uo_out = {5'b00000, rx_valid, tx_busy, txd};

  // uio bidirectional direction is controlled live:
  // uio_load_mode = 1 -> input mode (uio_oe = 0) to accept tx_data
  // uio_load_mode = 0 -> output mode (uio_oe = 0xFF) to present rx_data
  assign uio_out = uio_load_mode ? 8'h00 : rx_data;
  assign uio_oe  = uio_load_mode ? 8'h00 : 8'hFF;

  // List all unused inputs to prevent compiler/linter warnings
  wire _unused = &{ena, ui_in[7:3], 1'b0};

endmodule
