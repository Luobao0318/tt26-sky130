module control_unit (
    input wire clk,
    input wire rst_n,
    input wire [6:0] opcode,  // IR[6:0]
    input wire [2:0] funct3,  // IR[14:12]
    input wire mem_ready,
    // MUX选择信号
    output reg sel_alu_in1,
    output reg sel_alu_in2,
    // 子模块使能信号
    output reg reg_write_en,
    output reg mem_read_en,
    output reg mem_write_en,
    output reg [3:0] alu_op,
    output wire [3:0] current_state  // 连续赋值
);

    // FSM
    localparam S_FETCH = 4'd0;  // 不能在模块实例化时被外部修改
    localparam S_DECODE = 4'd1;
    localparam S_EXECUTE_ALU = 4'd2;
    localparam S_WRITEBACK_ALU = 4'd3;
    localparam S_EXECUTE_MEM = 4'd4;
    localparam S_MEM_READ = 4'd5;
    localparam S_WRITEBACK_MEM = 4'd6;
    localparam S_MEM_WRITE = 4'd7;
    localparam S_EXECUTE_BRANCH = 4'd8;
    localparam S_EXECUTE_JUMP = 4'd9;

    reg [3:0] state, next_state;
    assign current_state = state;

    // 状态转移时序
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_FETCH;
        else state <= next_state;
    end

    always @(*) begin
        sel_alu_in1 = 1'b0;
        sel_alu_in2 = 1'b0;
        reg_write_en = 1'b0;
        mem_read_en = 1'b0;
        mem_write_en = 1'b0;
        alu_op = 1'b0;
        next_state = S_FETCH;

        case (state)
            S_FETCH: begin
                next_state = mem_ready ? S_DECODE : S_FETCH;
                mem_read_en = 1'b1;
            end

            S_DECODE: begin
                if (opcode == 7'b0110011 || opcode == 7'b0010011 || opcode == 7'b0110111 || opcode == 7'b0010111)  // R/I/lui/auipc
                    next_state = S_EXECUTE_ALU;
                else if (opcode == 7'b0000011 || opcode == 7'b0100011)  // load/store
                    next_state = S_EXECUTE_MEM;
                else if (opcode == 7'b1100011)  // branch
                    next_state = S_EXECUTE_BRANCH;
                else if (opcode == 7'b1101111 || opcode == 7'b1100111)  // jal/jalr
                    next_state = S_EXECUTE_JUMP;
                else next_state = S_FETCH;
            end

            S_EXECUTE_ALU: begin
                next_state = S_WRITEBACK_ALU;
                sel_alu_in1 = (opcode == 7'b0110011) ? 1'b1 : 1'b0;  // auipc选pc，其余A
                sel_alu_in2 = (opcode == 7'b0010011) ? 1'b1 : 1'b0;  // I型选立即数(0)，R型选B(1)
                if (opcode == 7'b0110111) begin
                    alu_op = 4'b1010;  // lui
                end
                else if (opcode == 7'b0010111) begin
                    alu_op = 4'b0000;  // auipc
                end
                else begin
                    case (funct3)
                        3'b000: alu_op = 4'b0000;  // add/sub
                        3'b001: alu_op = 4'b0101;  // sll
                        3'b010: alu_op = 4'b1000;  // slt
                        3'b011: alu_op = 4'b1001;  // sltu
                        3'b101: alu_op = 4'b0110;  // srl
                        3'b111: alu_op = 4'b0010;  // and
                        3'b110: alu_op = 4'b0011;  // or
                        3'b100: alu_op = 4'b0100;  // xor
                        default: alu_op = 4'b0000;
                    endcase
                end
            end

            S_WRITEBACK_ALU: begin
                next_state = S_FETCH;
                reg_write_en = 1'b1;
            end

            S_EXECUTE_MEM: begin
                next_state = (opcode == 7'b0000011) ? S_MEM_READ : S_MEM_WRITE;
                sel_alu_in1 = 1'b0;
                sel_alu_in2 = 1'b0;  // 立即数偏移
                alu_op = 4'b0000;
            end

            S_MEM_READ: begin
                next_state = mem_ready ? S_WRITEBACK_MEM : S_MEM_READ;
                mem_read_en = 1'b1;
            end

            S_WRITEBACK_MEM: begin
                next_state = S_FETCH;
                reg_write_en = 1'b1;
            end

            S_MEM_WRITE: begin
                next_state = mem_ready ? S_FETCH : S_MEM_WRITE;
                mem_write_en = 1'b1;
            end

            S_EXECUTE_BRANCH: begin
                next_state = S_FETCH;
                sel_alu_in1 = 1'b0;  // A
                sel_alu_in2 = 1'b1;  // B
                alu_op = 4'b0001;  // 算术相减判断是否相等
            end

            S_EXECUTE_JUMP: begin
                next_state = S_WRITEBACK_ALU;
            end

            default: next_state = S_FETCH;
        endcase
    end

endmodule
