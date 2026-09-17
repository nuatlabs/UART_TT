/*
 * Copyright (c) 2026 NUAT Labs
 * SPDX-License-Identifier: Apache-2.0
 *
 * uart_rx
 * -------
 * Hardware 8N1 UART receiver module.
 *
 * Features:
 * - 2-stage flip-flop synchronizer on asynchronous serial input (rxd)
 *   to mitigate metastability.
 * - Mid-bit sampling (at BAUD_DIV / 2) for maximum noise margin.
 * - Single-cycle synchronous rx_valid pulse when byte reception completes.
 * - Registered rx_data output holding the last valid received byte.
 */
`default_nettype none

module uart_rx #(
    parameter BAUD_DIV = 4   // Clock cycles per baud bit period
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rxd,           // Serial input line (asynchronous)
    output reg  [7:0] rx_data,       // Received parallel byte
    output reg        rx_valid       // 1-cycle active-high pulse on reception complete
);

  localparam DIVW = (BAUD_DIV > 1) ? $clog2(BAUD_DIV) : 1;
  localparam HALF = BAUD_DIV / 2;

  localparam ST_IDLE  = 3'd0;
  localparam ST_START = 3'd1;
  localparam ST_DATA  = 3'd2;
  localparam ST_STOP  = 3'd3;

  reg [2:0]      state, state_n;
  reg [2:0]      bit_idx, bit_idx_n;
  reg [DIVW-1:0] baud_cnt, baud_cnt_n;
  reg [7:0]      shift_reg, shift_reg_n;

  // 2-stage synchronizer to prevent metastability on async serial input
  reg rxd_sync1, rxd_sync2;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rxd_sync1 <= 1'b1;
      rxd_sync2 <= 1'b1;
    end else begin
      rxd_sync1 <= rxd;
      rxd_sync2 <= rxd_sync1;
    end
  end

  wire baud_tick = (baud_cnt == (BAUD_DIV - 1));
  wire mid_tick  = (baud_cnt == HALF[DIVW-1:0]);

  // ---------------- State Register ----------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= ST_IDLE;
      bit_idx   <= 3'd0;
      baud_cnt  <= {DIVW{1'b0}};
      shift_reg <= 8'd0;
    end else begin
      state     <= state_n;
      bit_idx   <= bit_idx_n;
      baud_cnt  <= baud_cnt_n;
      shift_reg <= shift_reg_n;
    end
  end

  // ---------------- Next-State and Datapath Combinational Logic ----------------
  always @(*) begin
    state_n     = state;
    bit_idx_n   = bit_idx;
    baud_cnt_n  = baud_cnt;
    shift_reg_n = shift_reg;

    case (state)
      ST_IDLE: begin
        baud_cnt_n = {DIVW{1'b0}};
        if (!rxd_sync2) begin    // Falling edge detected -> start bit begins
          state_n = ST_START;
        end
      end

      ST_START: begin
        if (baud_tick) begin
          baud_cnt_n = {DIVW{1'b0}};
          bit_idx_n  = 3'd0;
          state_n    = ST_DATA;
        end else begin
          baud_cnt_n = baud_cnt + 1'b1;
        end
      end

      ST_DATA: begin
        if (mid_tick) begin
          shift_reg_n = {rxd_sync2, shift_reg[7:1]}; // Sample at midpoint; shift in LSB first
        end
        if (baud_tick) begin
          baud_cnt_n = {DIVW{1'b0}};
          if (bit_idx == 3'd7)
            state_n = ST_STOP;
          else
            bit_idx_n = bit_idx + 1'b1;
        end else begin
          baud_cnt_n = baud_cnt + 1'b1;
        end
      end

      ST_STOP: begin
        if (baud_tick) begin
          baud_cnt_n = {DIVW{1'b0}};
          state_n    = ST_IDLE;
        end else begin
          baud_cnt_n = baud_cnt + 1'b1;
        end
      end

      default: state_n = ST_IDLE;
    endcase
  end

  // ---------------- Registered Output Generation ----------------
  // rx_valid pulses for exactly 1 clock cycle upon STOP -> IDLE transition
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_data  <= 8'd0;
      rx_valid <= 1'b0;
    end else begin
      rx_valid <= (state == ST_STOP) && baud_tick;
      if ((state == ST_STOP) && baud_tick) begin
        rx_data <= shift_reg;
      end
    end
  end

endmodule
