/*
 * Copyright (c) 2026 Luo Yue
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_Luobao0318 (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  reg [31:0] PC;
  reg [31:0] IR;  // instruction register
  reg [31:0] MDR; // memory data register
  reg [31:0] ALUOut;

  reg [31:0] RAM [0:15];

  // 子模块内部信号
  wire sel_alu_in1;
  wire sel_alu_in2;
  wire reg_write_en;
  wire mem_read_en;
  wire mem_write_en;
  wire [3:0] alu_op;
  wire [3:0] current_state;

  wire [31:0] reg_rdata1, reg_rdata2;
  wire [31:0] alu_result;
  wire alu_zero;

  wire rd_illegal = (IR[6:0] != 7'b0100011 && IR[6:0] != 7'b1100011) && IR[11];  // store和branch无rd
  wire rs1_illegal = (IR[6:0] != 7'b0110111 && IR[6:0] != 7'b1101111) && IR[19]; // lui和jal无rs1
  wire rs2_illegal = (IR[6:0] == 7'b0110011 || IR[6:0] == 7'b0100011 || IR[6:0] == 7'b1100011) && IR[24]; // 仅R, store, branch有rs2
  wire illegal_instr = rd_illegal || rs1_illegal || rs2_illegal;

  // 实例化
  control_unit ctrl_inst (
      .clk(clk), .rst_n(rst_n),
      .opcode(IR[6:0]), .funct3(IR[14:12]),
      .mem_ready(1'b1),  // 默认单周期即时就绪
      .sel_alu_in1(sel_alu_in1), .sel_alu_in2(sel_alu_in2),
      .reg_write_en(reg_write_en),
      .mem_read_en(mem_read_en),
      .mem_write_en(mem_write_en),
      .alu_op(alu_op),
      .current_state(current_state)
  );

  wire [7:0] x1_low8;

  reg_file rf_inst (
      .clk(clk),
      .rst_n(rst_n),
      .raddr1(IR[18:15]),  // 19位为0
      .raddr2(IR[23:20]),
      .waddr(IR[10:7]),
      .wdata((current_state == 4'd6) ? MDR : ALUOut),
      .we(reg_write_en && !illegal_instr),
      .rdata1(reg_rdata1), .rdata2(reg_rdata2),
      .x1_low8(x1_low8)
  );

  // 立即数生成
  reg [31:0] imm;
  always @(*) begin
    case (IR[6:0])
      7'b0010011, 7'b0000011, 7'b1100111: imm = {{21{IR[31]}}, IR[30:25], IR[24:21], IR[20]};  // I, load, jalr
      7'b0100011: imm = {{21{IR[31]}}, IR[30:25], IR[11:8], IR[7]};  // S
      7'b1100011: imm = {{20{IR[31]}}, IR[7], IR[30:25], IR[11:8], 1'b0};  // B
      7'b0110111, 7'b0010111: imm = {IR[31], IR[30:20], IR[19:12], 12'b0};  // lui, auipc
      7'b1101111: imm = {{12{IR[31]}}, IR[19:12], IR[20], IR[30:25], IR[24:21], 1'b0};  // jal
      default: imm = 32'd0;
    endcase
  end

  wire [31:0] alu_in1 = sel_alu_in1 ? (PC - 4) : reg_rdata1;
  wire [31:0] alu_in2 = sel_alu_in2 ? reg_rdata2 : imm;

  // R型指令下add与sub判断
  wire [3:0] final_alu_op = (alu_op == 4'b0000 && IR[6:0] == 7'b0110011 && IR[30]) ? 4'b0001 :
                            (alu_op == 4'b0110 && IR[30]) ? 4'b0111 :
                            alu_op;

  alu alu_inst (
      .in1(alu_in1), .in2(alu_in2),
      .op(final_alu_op),
      .out(alu_result),
      .zero(alu_zero)
  );

  /***************************************************************************************************/

  wire [3:0] ram_addr = (current_state == 4'd0) ? PC[5:2] : ALUOut[5:2];  // 取指用PC，访存用ALUOut

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      PC <= 32'd0;
      IR <= 32'd0;
      MDR <= 32'd0;
      ALUOut <= 32'd0;
    end
    else begin
      case (current_state)
        4'd0: begin  // S_FETCH
          IR <= RAM[ram_addr];
          PC <= PC + 4;
        end
        4'd1: begin  // S_DECODE
          ALUOut <= PC;  // 备份PC
        end
        4'd2: begin
          ALUOut <= alu_result;  // 暂存ALU结果
        end
        4'd3: begin
          // none
        end
        4'd4: begin
          ALUOut <= alu_result;
        end
        4'd5: begin
          MDR <= RAM[ram_addr];
        end
        4'd6: begin
          // PC <= ALUOut;
        end
        4'd7: begin
          if (mem_write_en) begin
            RAM[ram_addr] <= reg_rdata2;  // store
          end
          // PC <= ALUOut;
        end
        4'd8: begin
          if (alu_zero && IR[14:12] == 3'b000) begin  // beq
            PC <= PC - 4 + imm;  // PC_old + imm
          end
          else if (!alu_zero && IR[14:12] == 3'b001) begin  // bne
            PC <= PC - 4 + imm;
          end
          else begin
            PC <= ALUOut;  // 顺序执行下一条指令
          end
        end
        4'd9: begin  // S_EXECUTE_JUMP
          if (IR[3]) begin  // jal
            PC <= PC - 4 + imm;
          end
          else begin  // jalr
            PC <= (reg_rdata1+imm) & 32'hfffffffe;  // 寄存器基址+偏移量，且最低位置零
          end
        end
      endcase
    end
  end

  // x1的值直接输出
  assign uo_out = x1_low8; // x1低8位
  assign uio_out = 0;  // 双向IO输出值
  assign uio_oe = 0;   // 双向IO输出使能信号

  wire _unused = &{ena, uio_in, 1'b0};

endmodule
