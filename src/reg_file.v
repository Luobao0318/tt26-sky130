module reg_file (
    input wire clk,
    input wire rst_n,
    input wire [3:0] raddr1,
    input wire [3:0] raddr2,
    input wire [3:0] waddr,
    input wire [31:0] wdata,
    input wire we,  // 写使能
    output wire [31:0] rdata1,
    output wire [31:0] rdata2,
    output wire [7:0] x1_low8
);

    reg [31:0] rf [1:15];  // x0恒为0

    assign rdata1 = (raddr1 == 4'd0) ? 32'd0 : rf[raddr1];
    assign rdata2 = (raddr2 == 4'd0) ? 32'd0 : rf[raddr2];
    assign x1_low8 = rf[1][7:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 1; i < 16; i = i + 1) begin
                rf[i] <= 32'd0;
            end
        end
        else if (we && (waddr != 4'd0)) begin
            rf[waddr] <= wdata;
        end
    end

endmodule
