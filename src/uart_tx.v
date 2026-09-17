/*
 * Copyright (c) 2026 NUAT Labs
 * SPDX-License-Identifier: Apache-2.0
 *
 * uart_tx
 * -------
 * Hardware 8N1 UART transmitter module.
 *
 * Protocol:
 * - 1 Start bit (logic 0)
 * - 8 Data bits (LSB first)
 * - 1 Stop bit (logic 1)
 *
 * Baud rate is set by BAUD_DIV (clock cycles per bit period):
 * BAUD_DIV = clk_hz / baud_rate.
 */
`default_nettype none

module uart_tx #(
    parameter BAUD_DIV = 4   // Clock cycles per baud bit period
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,      // 1-cycle pulse: latch tx_data and start transmit
    input  wire [7:0] tx_data,       // Parallel byte to send
    output reg        txd,           // Serial output line (idles high)
    output reg        tx_busy        // High while transmitting
);

  localparam DIVW = (BAUD_DIV > 1) ? $clog2(BAUD_DIV) : 1;

  localparam ST_IDLE  = 3'd0;
  localparam ST_START = 3'd1;
  localparam ST_DATA  = 3'd2;
  localparam ST_STOP  = 3'd3;

  reg [2:0]      state, state_n;
  reg [2:0]      bit_idx, bit_idx_n;
  reg [DIVW-1:0] baud_cnt, baud_cnt_n;
  reg [7:0]      shift_reg, shift_reg_n;

  wire baud_tick = (baud_cnt == (BAUD_DIV - 1));

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
        if (tx_start) begin
          shift_reg_n = tx_data;
          state_n     = ST_START;
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
        if (baud_tick) begin
          baud_cnt_n  = {DIVW{1'b0}};
          shift_reg_n = shift_reg >> 1;
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

  // ---------------- Moore Output Logic ----------------
  always @(*) begin
    tx_busy = (state != ST_IDLE);
    case (state)
      ST_IDLE:  txd = 1'b1;
      ST_START: txd = 1'b0;
      ST_DATA:  txd = shift_reg[0];
      ST_STOP:  txd = 1'b1;
      default:  txd = 1'b1;
    endcase
  end

endmodule
