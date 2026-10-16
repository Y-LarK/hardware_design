// ============================================================================
// mdu.v —— 组合乘除单元（单周期版）
// ----------------------------------------------------------------------------
// 设计口径（DESIGN.md §3.6 / §10 阶段 1）：
//   单周期阶段用「组合逻辑乘法器/除法器」，一拍出结果；代价是组合路径长、
//   拖低主频。这是与流水线版（多周期 MDU + 握手）的关键区别，答辩要讲清。
// 乘法接口：mul_valid=1 时按 mul_op 输出
//   mul_op=0 -> MUL.W   ：64 位乘积低 32 位
//   mul_op=1 -> MULH.W  ：64 位有符号乘积高 32 位
//   mul_op=2 -> MULH.WU ：64 位无符号乘积高 32 位（手册：高 32 位原样写入 rd）
// 除法接口：div_valid=1 时按 div_op 输出
//   div_op=0 -> DIV.W  （有符号商）    div_op=1 -> DIV.WU（无符号商）
//   div_op=2 -> MOD.W  （有符号余数）  div_op=3 -> MOD.WU（无符号余数）
// 边界情况（DESIGN.md §3.6，固定取值并写入文档）：
//   除 0      ：商 = 全 1（0xFFFFFFFF），余数 = 被除数
//   -2^31 / -1：商溢出，本设计固定取 -2^31（0x80000000），余数 0
//   余数符号  ：与被除数同号（Verilog % 天然满足）
// ============================================================================
module mdu (
    input  wire [31:0] a,        // 被乘数 / 被除数（= rj）
    input  wire [31:0] b,        // 乘数   / 除数   （= rk）
    input  wire [1:0]  mul_op,   // 乘法类型
    input  wire [1:0]  div_op,   // 除法类型
    input  wire        mul_valid,// 乘法类指令有效
    input  wire        div_valid,// 除法类指令有效
    output wire [31:0] mul_res,  // 乘法结果
    output wire [31:0] div_res   // 除法结果
);

    // ---- 乘法：补码乘法低 32 位与无符号相同，直接取无符号积的低半 ----
    wire [63:0] prod_u = {32'd0, a} * {32'd0, b};          // 无符号 64 位乘积
    wire [63:0] prod_s = $signed(a) * $signed(b);          // 有符号 64 位乘积

    assign mul_res = (mul_op == 2'd1) ? prod_s[63:32] :    // MULH.W
                     (mul_op == 2'd2) ? prod_u[63:32] :    // MULH.WU（手册：无符号高 32 位写入 rd）
                     prod_u[31:0];                          // MUL.W（低 32 位）

    // ---- 除法：组合逻辑直接运算（工具推断除法器） ----
    reg [31:0] quo, rem;
    always @(*) begin
        if (!div_valid) begin
            quo = 32'd0;
            rem = 32'd0;
        end else if (b == 32'd0) begin
            // 除 0：固定「商=全 1，余数=被除数」，不触发例外
            quo = 32'hFFFFFFFF;
            rem = a;
        end else if (div_op[0] == 1'b1) begin
            // 无符号除法：DIV.WU / MOD.WU
            quo = a / b;
            rem = a % b;
        end else if (a == 32'h80000000 && b == 32'hFFFFFFFF) begin
            // -2^31 / -1 溢出：固定取 商=-2^31，余数=0
            quo = 32'h80000000;
            rem = 32'd0;
        end else begin
            // 有符号除法：DIV.W / MOD.W（余数与被除数同号）
            quo = $signed(a) / $signed(b);
            rem = $signed(a) % $signed(b);
        end
    end

    assign div_res = (div_op == 2'd0 || div_op == 2'd1) ? quo : rem;

endmodule
