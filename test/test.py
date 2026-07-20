import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

gate_level = os.environ.get('GATES') == 'yes'

# 辅助函数：将程序写入内部 RAM
def write_program_to_ram(dut, program):
    """
    program: dict {word_addr: instruction_word}
    word_addr 是 RAM 的索引 (0~15)
    """
    for addr, instr in program.items():
        if 0 <= addr < 16:
            dut.user_project.RAM[addr].value = instr

@cocotb.test()
async def test_addi(dut):
    """执行 addi x1, x0, 50，然后检查 x1 低8位"""
    dut._log.info("Starting simple addi test")

    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    dut._log.info("Reset released")

    # 将程序写入 RAM：地址0: addi x1, x0, 50 (0x03200093)
    program = {0: 0x03200093}  # addi x1, x0, 50
    write_program_to_ram(dut, program)

    # 等待足够周期让指令完成（取指->译码->执行->写回）
    await ClockCycles(dut.clk, 20)

    # 读取 x1 寄存器的值（低8位输出到 uo_out）
    x1_low8 = int(dut.uo_out.value)
    dut._log.info(f"x1 low 8 bits = {x1_low8}, expected 50")
    assert x1_low8 == 50, f"x1_low8 is {x1_low8}, expected 50"
    dut._log.info("addi test passed")

@cocotb.test(skip=gate_level)
async def test_loop_branch(dut):
    """测试循环和分支指令（使用您的原始程序）"""
    dut._log.info("Starting loop/branch test")

    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    dut._log.info("Reset released")

    # 原始程序（注意小端序，地址为 word 地址）
    program = {
        0: 0x00500093,   # addi x1, x0, 5
        1: 0x00100113,   # addi x2, x0, 1
        2: 0x402080b3,   # sub x1, x1, x2
        3: 0xFE009EE3,   # bnez x1, -4 (循环)
        4: 0x00000013    # nop
    }
    write_program_to_ram(dut, program)

    # 等待执行完成（最多 150 周期）
    max_cycles = 150
    for _ in range(max_cycles):
        await FallingEdge(dut.clk)
        try:
            pc = int(dut.user_project.PC.value)
            if pc >= 20:  # 期望 PC 达到 20（指令 5 的地址）
                break
        except ValueError:
            pass
    else:
        assert False, "Loop did not finish within time"

    # 检查寄存器值
    x1 = int(dut.user_project.rf_inst.rf[1].value)
    x2 = int(dut.user_project.rf_inst.rf[2].value)
    pc = int(dut.user_project.PC.value)
    dut._log.info(f"x1={x1}, x2={x2}, PC={pc}")
    assert x1 == 0, f"x1 expected 0, got {x1}"
    assert x2 == 1, f"x2 expected 1, got {x2}"
    assert pc == 20, f"PC expected 20, got {pc}"
    dut._log.info("Loop/branch test passed")

@cocotb.test(skip=gate_level)
async def test_illegal_instructions(dut):
    """测试非法指令保护（期望非法指令不被执行）"""
    dut._log.info("Starting illegal instruction test")

    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    dut._log.info("Reset released")

    # 程序包含非法指令（例如 0x02A00093 可能合法，但这里按原样保留）
    program = {
        0: 0x02A00093,   # addi x1, x0, 42 (合法)
        1: 0x00A00893,   # 可能非法
        2: 0x00A90093,   # 可能非法
        3: 0x014100b3,   # 可能非法
        4: 0x00000013    # nop
    }
    write_program_to_ram(dut, program)

    await ClockCycles(dut.clk, 30)

    x1 = int(dut.user_project.rf_inst.rf[1].value)
    dut._log.info(f"x1={x1}, expected 42 (unchanged)")
    assert x1 == 42, f"x1 modified to {x1}, illegal instruction protection failed"
    dut._log.info("Illegal instruction test passed")

#################################################################
# 保留 RISCOF 测试（用于门级仿真和回归）
def load_elf_program(elf_path):
    program = {}
    with open(elf_path, 'rb') as f:
        elffile = ELFFile(f)
        for segment in elffile.iter_segments():
            if segment['p_type'] == 'PT_LOAD':
                data = segment.data()
                paddr = segment['p_paddr']
                for i in range(0, len(data), 4):
                    chunk = data[i:i+4]
                    if len(chunk) < 4:
                        break
                    word_addr = (paddr + i) >> 2
                    program[word_addr] = int.from_bytes(chunk, byteorder='little')
    return program

def get_signature_addresses(elf_path):
    with open(elf_path, 'rb') as f:
        elffile = ELFFile(f)
        symtab = elffile.get_section_by_name('.symtab')
        if not symtab:
            raise ValueError("No symbol table found in ELF!")
        begin_sig = None
        end_sig = None
        for symbol in symtab.iter_symbols():
            if symbol.name == 'begin_signature':
                begin_sig = symbol['st_value']
            elif symbol.name == 'end_signature':
                end_sig = symbol['st_value']
        return begin_sig, end_sig

@cocotb.test(skip=not os.environ.get('TEST_ELF_PATH'))
async def test_riscof_run(dut):
    from elftools.elf.elffile import ELFFile
    elf_path = os.environ.get('TEST_ELF_PATH')
    sig_out_path = os.environ.get('TEST_SIG_OUT_PATH')
    dut._log.info(f"Running RISCOF ELF: {elf_path}")

    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    dut._log.info("Reset released")

    # 将 ELF 加载到内部 RAM（仅前 16 个字）
    program = load_elf_program(elf_path)
    for addr, instr in program.items():
        if addr < 16:
            dut.user_project.RAM[addr].value = instr

    # 等待足够周期（根据 ELF 大小调整）
    await ClockCycles(dut.clk, 1500)

    begin_addr, end_addr = get_signature_addresses(elf_path)
    dut._log.info(f"Dumping signature from 0x{begin_addr:x} to 0x{end_addr:x}")

    with open(sig_out_path, 'w') as sf:
        for addr in range(begin_addr, end_addr, 4):
            word_idx = (addr >> 2) & 0xF
            val = int(dut.user_project.RAM[word_idx].value)
            sf.write(f"{val:08x}\n")

    dut._log.info("Signature dump completed successfully")