module alu (
    input wire [31:0] in1,
    input wire [31:0] in2,
    input wire [3:0] op,   // control_unit的alu_op
    output reg [31:0] out,
    output wire zero   // zero flag
);

    always @(*) begin
        case (op)
            4'b0000: out = in1 + in2;
            4'b0001: out = in1 - in2;
            4'b0010: out = in1 & in2;
            4'b0011: out = in1 | in2;
            4'b0100: out = in1 ^ in2;
            4'b0101: out = in1 << in2[4:0];  // sll
            4'b0110: out = in1 >> in2[4:0];  // srl
            4'b0111: out = $signed(in1) >>> in2[4:0];  // sra
            4'b1000: out = ($signed(in1) < $signed(in2)) ? 32'd1 : 32'd0; // slt
            4'b1001: out = (in1 < in2) ? 32'd1 : 32'd0;  // sltu
            4'b1010: out = in2;  // lui
            default: out = 32'd0;
        endcase
    end

    assign zero = (out == 32'd0);

endmodule
