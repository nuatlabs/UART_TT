# SPDX-FileCopyrightText: © 2026 NUAT Labs
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

BAUD_DIV = 4  # Must match the value hardcoded in project.v

# ui_in bit positions
BIT_RXD           = 0
BIT_TX_START      = 1
BIT_UIO_LOAD_MODE = 2


def ui_in_word(rxd=1, tx_start=0, load_mode=0):
    return (rxd << BIT_RXD) | (tx_start << BIT_TX_START) | (load_mode << BIT_UIO_LOAD_MODE)


async def reset(dut):
    dut.ena.value = 1
    dut.ui_in.value = ui_in_word(rxd=1, tx_start=0, load_mode=0)
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def loopback_pump(dut, ctrl, cycles):
    """Sole writer of dut.ui_in while active: every clock cycle, copies
    uo_out[0] (txd) onto ui_in[0] (rxd) -- exactly emulating an external
    wire jumper from TX to RX pin -- combined with tx_start/load_mode taken
    from the shared `ctrl` dict (mutated by the test body, never by
    writing dut.ui_in directly, to avoid a two-writer race)."""
    for _ in range(cycles):
        await RisingEdge(dut.clk)
        txd = (dut.uo_out.value.to_unsigned() >> 0) & 1
        dut.ui_in.value = ui_in_word(rxd=txd, tx_start=ctrl["tx_start"], load_mode=ctrl["load_mode"])


@cocotb.test()
async def test_uart_tx_shape(dut):
    """Send one byte and verify the serial waveform: start bit (0),
    8 data bits LSB-first, stop bit (1), and tx_busy timing."""
    dut._log.info("Start: TX waveform shape verification")
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

    test_byte = 0xA5  # 1010_0101
    dut.uio_in.value = test_byte
    dut.ui_in.value = ui_in_word(rxd=1, tx_start=1, load_mode=1)
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = ui_in_word(rxd=1, tx_start=0, load_mode=1)

    await ClockCycles(dut.clk, 1)
    assert (dut.uo_out.value.to_unsigned() >> 1) & 1 == 1, "tx_busy should be high during transmission"

    expected_bits = [0] + [(test_byte >> i) & 1 for i in range(8)] + [1]
    sampled_bits = []
    for _ in expected_bits:
        await ClockCycles(dut.clk, BAUD_DIV // 2)
        sampled_bits.append((dut.uo_out.value.to_unsigned() >> 0) & 1)
        await ClockCycles(dut.clk, BAUD_DIV - (BAUD_DIV // 2))

    assert sampled_bits == expected_bits, f"Expected {expected_bits}, got {sampled_bits}"
    dut._log.info(f"TX waveform verified for byte 0x{test_byte:02X}: {sampled_bits}")

    await ClockCycles(dut.clk, 4)
    assert (dut.uo_out.value.to_unsigned() >> 1) & 1 == 0, "tx_busy should drop after the stop bit"


@cocotb.test()
async def test_uart_loopback_single_byte(dut):
    """True external-style loopback: route txd to rxd every cycle,
    transmit a byte, and confirm the RX side reconstructs it exactly
    via rx_valid pulse and rx_data latching."""
    dut._log.info("Start: single-byte TX->RX loopback test")
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

    test_byte = 0x3C
    dut.uio_in.value = test_byte
    ctrl = {"tx_start": 1, "load_mode": 1}
    pump = cocotb.start_soon(loopback_pump(dut, ctrl, 200))
    await ClockCycles(dut.clk, 2)
    ctrl["tx_start"] = 0

    for _ in range(150):
        await RisingEdge(dut.clk)
        if (dut.uo_out.value.to_unsigned() >> 2) & 1:
            break
    else:
        assert False, "rx_valid never pulsed -- receiver did not see the frame"

    ctrl["load_mode"] = 0  # Switch uio to output mode to read rx_data
    await ClockCycles(dut.clk, 1)
    got = dut.uio_out.value.to_unsigned()
    assert got == test_byte, f"Expected loopback byte 0x{test_byte:02X}, got 0x{got:02X}"
    dut._log.info(f"Loopback successfully reconstructed byte 0x{test_byte:02X}")

    await pump


@cocotb.test()
async def test_uart_loopback_multiple_bytes(dut):
    """Send sequential bytes back-to-back through loopback and confirm
    each is reconstructed correctly, including stress corner cases 0x00 and 0xFF."""
    dut._log.info("Start: multi-byte loopback stress test")
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

    test_bytes = [0x00, 0xFF, 0x55, 0xAA, 0x81, 0x7E]
    ctrl = {"tx_start": 0, "load_mode": 1}
    pump = cocotb.start_soon(loopback_pump(dut, ctrl, 400 * len(test_bytes)))
    await ClockCycles(dut.clk, 1)

    for b in test_bytes:
        dut.uio_in.value = b
        ctrl["tx_start"] = 1
        await ClockCycles(dut.clk, 2)
        ctrl["tx_start"] = 0

        for _ in range(150):
            await RisingEdge(dut.clk)
            if (dut.uo_out.value.to_unsigned() >> 2) & 1:
                break
        else:
            assert False, f"rx_valid never pulsed for byte 0x{b:02X}"

        ctrl["load_mode"] = 0
        await ClockCycles(dut.clk, 1)
        got = dut.uio_out.value.to_unsigned()
        assert got == b, f"Expected 0x{b:02X}, got 0x{got:02X}"
        dut._log.info(f"Successfully received 0x{b:02X}")

        ctrl["load_mode"] = 1  # Revert to input mode for subsequent byte
        await ClockCycles(dut.clk, BAUD_DIV * 2)

    await pump
