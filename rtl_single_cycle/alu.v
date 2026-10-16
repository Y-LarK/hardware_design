// ============================================================================
// alu.v —— 算术逻辑单元（单周期）
// ----------------------------------------------------------------------------
// 输入：a（源操作数 A）、b（源操作数 B / 立即数）、pc（PCADDU12I 用）、
//       shamt（移位量：寄存器移位取 rk[4:0]，立即数移位取 ui5）
// 输出：result（32 位结果）
// 控制码 alu_op 由 control.v 译码产生，编码定义：
//   0=ADD  1=SUB  2=AND  3=OR  4=NOR  5=XOR
//   6=SLT（有符号 a<b） 7=SLTU（无符号 a<b）
//   8=SLL  9=SRL  10=SRA
//   11=LU12I（b<<12）  12=PCADD（pc + b<<12）
// 乘除（MUL/DIV/MOD 系列）由 mdu.v 独立处理，不在这里。
// ============================================================================
module alu (
    input  wire [31:0] a,       // 操作数 A
    input  wire [31:0] b,       // 操作数 B（寄存器 rk 或扩展后的立即数）
    input  wire [31:0] pc,      // 当前 PC（PCADDU12I 使用）
    input  wire [4:0]  shamt,   // 移位量
    input  wire [5:0]  alu_op,  // ALU 操作控制码
    output reg  [31:0] result   // 运算结果
);

    always @(*) begin
        case (alu_op)
            6'd0:  result = a + b;                       // ADD.W / ADDI.W / LD / ST（地址）
            6'd1:  result = a - b;                       // SUB.W
            6'd2:  result = a & b;                       // AND / ANDI
            6'd3:  result = a | b;                       // OR / ORI
            6'd4:  result = ~(a | b);                    // NOR
            6'd5:  result = a ^ b;                       // XOR / XORI
            6'd6:  result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;  // SLT / SLTI（有符号）
            6'd7:  result = (a < b) ? 32'd1 : 32'd0;     // SLTU / SLTUI（无符号）
            6'd8:  result = a << shamt;                  // SLL.W / SLLI.W（逻辑左移）
            6'd9:  result = a >> shamt;                  // SRL.W / SRLI.W（逻辑右移）
            6'd10: result = $signed(a) >>> shamt;        // SRA.W / SRAI.W（算术右移，保留符号位）
            6'd11: result = b << 12;                     // LU12I.W：rd = si20 << 12
            6'd12: result = pc + (b << 12);              // PCADDU12I：rd = PC + (si20 << 12)
            default: result = 32'd0;
        endcase
    end

endmodule
