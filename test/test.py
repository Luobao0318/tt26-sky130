import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge
from cocotb.handle import Force, Release

gate_level = os.environ.get('GATES') == 'yes'

async def mock_rom(dut, program):
    while True:
        await FallingEdge(dut.clk)
        try:
            pc_val = int(dut.user_project.PC.value)
            word_addr = (pc_val >> 2) & 0xF
            if word_addr in program:
                dut.user_project.rom_data.value = Force(int(program[word_addr]))
            else:
                dut.user_project.rom_data.value = Force(0x00000013)
        except ValueError:
            dut.user_project.rom_data.value = Force(0x00000013)

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start basic calculation simulation")

    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    dut._log.info("Reset released")

    await ClockCycles(dut.clk, 25)

    dut._log.info(f"Checking results: {dut.uo_out.value}")
    assert dut.uo_out.value == 50
    dut._log.info("Basic calculation test passed")

@cocotb.test(skip=gate_level)
async def test_loop_branch(dut):
    dut._log.info("Start Loop and Branch simulation")

    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    dut._log.info("Reset released")

    program = {
        0: 0x00500093,
        1: 0x00100113,
        2: 0x402080b3,
        3: 0xFE009EE3,
        4: 0x00000013
    }

    rom_task = cocotb.start_soon(mock_rom(dut, program))

    max_cycles = 150
    cycles = 0
    while cycles < max_cycles:
        await FallingEdge(dut.clk)
        cycles += 1
        try:
            pc_val = int(dut.user_project.PC.value)
            if pc_val >= 20:
                break
        except ValueError:
            pass
    else:
        assert False, f"Timeout: Loop did not finish within {max_cycles} cycles."

    try:
        x1_val = int(dut.user_project.rf_inst.rf[1].value)
        x2_val = int(dut.user_project.rf_inst.rf[2].value)
        pc_val = int(dut.user_project.PC.value)

        dut._log.info("Loop execution complete:")
        dut._log.info(f"  Register x1 final value: {x1_val} (expected: 0)")
        dut._log.info(f"  Register x2 value: {x2_val} (expected: 1)")
        dut._log.info(f"  PC final value: {pc_val} (expected: 20)")

        assert x1_val == 0, f"x1 is {x1_val}, expected 0"
        assert x2_val == 1, f"x2 is {x2_val}, expected 1"
        assert pc_val == 20, f"PC is {pc_val}, expected 20"
        dut._log.info("Loop and Branch test passed")
    finally:
        rom_task.cancel()
        dut.user_project.rom_data.value = Release()

@cocotb.test(skip=gate_level)
async def test_illegal_instructions(dut):
    dut._log.info("Start Illegal Instructions simulation")

    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    dut._log.info("Reset released")

    program = {
        0: 0x02A00093,
        1: 0x00A00893,
        2: 0x00A90093,
        3: 0x014100b3,
        4: 0x00000013
    }

    rom_task = cocotb.start_soon(mock_rom(dut, program))

    max_cycles = 50
    cycles = 0
    while cycles < max_cycles:
        await FallingEdge(dut.clk)
        cycles += 1
        try:
            pc_val = int(dut.user_project.PC.value)
            if pc_val >= 20:
                break
        except ValueError:
            pass
    else:
        assert False, f"Timeout: Instructions did not complete within {max_cycles} cycles."

    try:
        x1_val = int(dut.user_project.rf_inst.rf[1].value)
        dut._log.info("Illegal instruction check complete:")
        dut._log.info(f"  Register x1 value: {x1_val} (expected: 42)")

        assert x1_val == 42, f"x1 was modified to {x1_val}, illegal instruction protection failed"
        dut._log.info("Illegal instructions test passed")
    finally:
        rom_task.cancel()
        dut.user_project.rom_data.value = Release()