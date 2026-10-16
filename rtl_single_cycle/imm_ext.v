// ============================================================================
// imm_ext.v —— 立即数扩展单元
// ----------------------------------------------------------------------------
// 按指令类型从 32 位指令中取出立即数字段并扩展：
//   imm_sel=0：无立即数（输出 0）
//   imm_sel=1：si12（12 位有符号，符号扩展）—— ADDI.W / SLTI / SLTUI / LD.* / ST.*
//   imm_sel=2：ui12（12 位无符号，零扩展） —— ANDI / ORI / XORI（掩码语义）
//   imm_sel=3：si20（20 位有符号，符号扩展，ALU 内再 <<12）—— LU12I.W / PCADDU12I
// 注意（DESIGN.md §2.2 易错点）：SLTUI 的立即数虽然做无符号比较，但立即数
//   仍是符号扩展；ANDI/ORI/XORI 才是零扩展。本单元按 imm_sel 严格区分。
// ============================================================================
module imm_ext (
    input  wire [31:0] instr,    // 32 位指令
    input  wire [2:0]  imm_sel,  // 立即数类型选择
    output reg  [31:0] imm_out   // 扩展后的立即数
);

    wire [11:0] si12 = instr[21:10];   // 2RI12 立即数字段
    wire [19:0] si20 = instr[24:5];    // 2RI20 立即数字段

    always @(*) begin
        case (imm_sel)
            3'd1: imm_out = {{20{si12[11]}}, si12};            // 符号扩展 si12
            3'd2: imm_out = {20'd0, si12};                     // 零扩展 ui12
            3'd3: imm_out = {{12{si20[19]}}, si20};            // 符号扩展 si20（<<12 在 ALU 做）
            default: imm_out = 32'd0;
        endcase
    end

endmodule
