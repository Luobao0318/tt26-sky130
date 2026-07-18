<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This design implements a multi‑cycle RV32E processor. It provides 16 general‑purpose registers, a multi‑cycle control state machine, and separate instruction and data memory blocks. The core supports a subset of RV32E arithmetic, logic, branch, and control instructions.

To ensure compliance with the RV32E register specification, the processor includes a small hardware check that flags any instruction or memory access involving registers x16–x31. When such an illegal reference is detected, the instruction is trapped and its write‑back stage is suppressed.

## How to test

The processor is evaluated in RTL simulation with a testbench. The built‑in ROM contains a small demo program that adds 20 and 30 and stores the result in x1; the low 8 bits of x1 are exposed on uo_out, making it easy to confirm correct execution.

## External hardware

List external hardware used in your project (e.g. PMOD, LED display, etc), if any
