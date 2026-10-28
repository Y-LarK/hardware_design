// ============================================================================
// control.v —— 主控制器（指令译码）
// ----------------------------------------------------------------------------
// 输入 32 位指令，输出全套控制信号。按 LA32R 六种编码格式分派：
//   3R   [31:15]：算术/逻辑/移位/乘除（28 条，opcode 与官方手册附录 B 逐位核实）
//   2RI5 [31:15]：SLLI.W / SRLI.W / SRAI.W
//   2RI12[31:22]：SLTI / SLTUI / ADDI.W / ANDI / ORI / XORI / LD.* / ST.*
//   2RI20[31:25]：LU12I.W / PCADDU12I
//   2RI16[31:26]：JIRL / BEQ / BNE / BLT / BGE / BLTU / BGEU
//   I26  [31:26]：B / BL
// 输出：
//   ra1/ra2    寄存器堆读地址（ra1=rj；3R 的 ra2=rk，其余 ra2=rd）
//   reg_we     寄存器写使能（写 r0 被寄存器堆忽略）
//   alu_src    ALU B 源：0=寄存器 rk，1=立即数
//   imm_sel    立即数类型（见 imm_ext.v）
//   alu_op     ALU 操作码（见 alu.v）
//   mem_wen    DMEM 写使能；mem_sel 访存类型
//   wb_sel     写回源：0=ALU 1=DMEM 2=MUL 3=DIV 4=PC+4（BL/JIRL）
//   mul_valid/div_valid/mul_op/div_op  乘除控制
//   branch_op  0=无 1=BEQ 2=BNE 3=BLT 4=BGE 5=BLTU 6=BGEU
//   jump_op    0=无 1=B 2=BL 3=JIRL
//   shift_imm  移位量来源：1=立即数 ui5（instr[14:10]），0=寄存器 rk[4:0]
// ============================================================================
module control (
    input  wire [31:0] instr,
    output reg  [4:0]  ra1,
    output reg  [4:0]  ra2,
    output reg         reg_we,
    output reg         alu_src,
    output reg  [2:0]  imm_sel,
    output reg  [5:0]  alu_op,
    output reg         mem_wen,
    output reg  [2:0]  mem_sel,
    output reg  [2:0]  wb_sel,
    output reg         mul_valid,
    output reg         div_valid,
    output reg  [1:0]  mul_op,
    output reg  [1:0]  div_op,
    output reg  [2:0]  branch_op,
    output reg  [1:0]  jump_op,
    output reg         shift_imm
);

    always @(*) begin
        // ---------- 默认值 ----------
        ra1       = instr[9:5];    // rj
        ra2       = instr[4:0];    // 默认第二源 = rd
        reg_we    = 1'b0;
        alu_src   = 1'b0;
        imm_sel   = 3'd0;
        alu_op    = 6'd0;
        mem_wen   = 1'b0;
        mem_sel   = 3'd0;
        wb_sel    = 3'd0;
        mul_valid = 1'b0;
        div_valid = 1'b0;
        mul_op    = 2'd0;
        div_op    = 2'd0;
        branch_op = 3'd0;
        jump_op   = 2'd0;
        shift_imm = 1'b0;

        // ---------- 3R：算术 / 逻辑 / 寄存器移位（[31:15] 与手册附录 B 核实） ----------
        case (instr[31:15])
            17'h00020: begin // ADD.W rd,rj,rk
                ra2=instr[14:10]; reg_we=1'b1; alu_op=6'd0;  wb_sel=3'd0; end
            17'h00022: begin // SUB.W
                ra2=instr[14:10]; reg_we=1'b1; alu_op=6'd1;  wb_sel=3'd0; end
            17'h00024: begin // SLT（有符号小于）
                ra2=instr[14:10]; reg_we=1'b1; alu_op=6'd6;  wb_sel=3'd0; end
            17'h00025: begin // SLTU（无符号小于）
                ra2=instr[14:10]; reg_we=1'b1; alu_op=6'd7;  wb_sel=3'd0; end
            17'h00028: begin // NOR
                ra2=instr[14:10]; reg_we=1'b1; alu_op=6'd4;  wb_sel=3'd0; end
            17'h00029: begin // AND
                ra2=instr[14:10]; reg_we=1'b1; alu_op=6'd2;  wb_sel=3'd0; end
            17'h0002A: begin // OR
                ra2=instr[14:10]; reg_we=1'b1; alu_op=6'd3;  wb_sel=3'd0; end
            17'h0002B: begin // XOR
                ra2=instr[14:10]; reg_we=1'b1; alu_op=6'd5;  wb_sel=3'd0; end
            17'h0002E: begin // SLL.W（寄存器移位：移位量=rk[4:0]）
                ra2=instr[14:10]; reg_we=1'b1; alu_op=6'd8;  shift_imm=1'b0; wb_sel=3'd0; end
            17'h0002F: begin // SRL.W
                ra2=instr[14:10]; reg_we=1'b1; alu_op=6'd9;  shift_imm=1'b0; wb_sel=3'd0; end
            17'h00030: begin // SRA.W（算术右移）
                ra2=instr[14:10]; reg_we=1'b1; alu_op=6'd10; shift_imm=1'b0; wb_sel=3'd0; end
            17'h00038: begin // MUL.W（乘积低 32 位）
                ra2=instr[14:10]; reg_we=1'b1; mul_valid=1'b1; mul_op=2'd0; wb_sel=3'd2; end
            17'h00039: begin // MULH.W（有符号乘积高 32 位）
                ra2=instr[14:10]; reg_we=1'b1; mul_valid=1'b1; mul_op=2'd1; wb_sel=3'd2; end
            17'h0003A: begin // MULH.WU（无符号乘积高 32 位）
                ra2=instr[14:10]; reg_we=1'b1; mul_valid=1'b1; mul_op=2'd2; wb_sel=3'd2; end
            17'h00040: begin // DIV.W（有符号商）
                ra2=instr[14:10]; reg_we=1'b1; div_valid=1'b1; div_op=2'd0; wb_sel=3'd3; end
            17'h00041: begin // MOD.W（有符号余数）
                ra2=instr[14:10]; reg_we=1'b1; div_valid=1'b1; div_op=2'd2; wb_sel=3'd3; end
            17'h00042: begin // DIV.WU（无符号商）
                ra2=instr[14:10]; reg_we=1'b1; div_valid=1'b1; div_op=2'd1; wb_sel=3'd3; end
            17'h00043: begin // MOD.WU（无符号余数）
                ra2=instr[14:10]; reg_we=1'b1; div_valid=1'b1; div_op=2'd3; wb_sel=3'd3; end
            default: ; // 非 3R，交给下面的编码格式判断
        endcase

        // ---------- 2RI5：移位立即数（ui5 在 instr[14:10]，移位量直接取字段） ----------
        // 编码已用 binutils 实测核对：SLLI.W=0x81、SRLI.W=0x89、SRAI.W=0x91。
        // 0xA1 是 RCRI.W，不在本设计 46 条指令清单内，故不译码。
        case (instr[31:15])
            17'h00081: begin // SLLI.W rd,rj,ui5
                reg_we=1'b1; alu_op=6'd8;  shift_imm=1'b1; wb_sel=3'd0; end
            17'h00089: begin // SRLI.W
                reg_we=1'b1; alu_op=6'd9;  shift_imm=1'b1; wb_sel=3'd0; end
            17'h00091: begin // SRAI.W
                reg_we=1'b1; alu_op=6'd10; shift_imm=1'b1; wb_sel=3'd0; end
            default: ;
        endcase

        // ---------- 2RI12：立即数算术 / 逻辑 / 比较 / 访存 ----------
        case (instr[31:22])
            12'h008: begin // SLTI rd,rj,si12（符号扩展，有符号比较）
                reg_we=1'b1; alu_src=1'b1; imm_sel=3'd1; alu_op=6'd6; wb_sel=3'd0; end
            12'h009: begin // SLTUI rd,rj,si12 —— 易错点：立即数仍是符号扩展！
                reg_we=1'b1; alu_src=1'b1; imm_sel=3'd1; alu_op=6'd7; wb_sel=3'd0; end
            12'h00A: begin // ADDI.W rd,rj,si12
                reg_we=1'b1; alu_src=1'b1; imm_sel=3'd1; alu_op=6'd0; wb_sel=3'd0; end
            12'h00D: begin // ANDI rd,rj,ui12（零扩展，掩码语义）
                reg_we=1'b1; alu_src=1'b1; imm_sel=3'd2; alu_op=6'd2; wb_sel=3'd0; end
            12'h00E: begin // ORI rd,rj,ui12
                reg_we=1'b1; alu_src=1'b1; imm_sel=3'd2; alu_op=6'd3; wb_sel=3'd0; end
            12'h00F: begin // XORI rd,rj,ui12
                reg_we=1'b1; alu_src=1'b1; imm_sel=3'd2; alu_op=6'd5; wb_sel=3'd0; end
            12'h0A0: begin // LD.B rd,rj,si12（符号扩展字节）
                reg_we=1'b1; alu_src=1'b1; imm_sel=3'd1; alu_op=6'd0; mem_sel=3'd0; wb_sel=3'd1; end
            12'h0A1: begin // LD.H（符号扩展半字）
                reg_we=1'b1; alu_src=1'b1; imm_sel=3'd1; alu_op=6'd0; mem_sel=3'd1; wb_sel=3'd1; end
            12'h0A2: begin // LD.W
                reg_we=1'b1; alu_src=1'b1; imm_sel=3'd1; alu_op=6'd0; mem_sel=3'd2; wb_sel=3'd1; end
            12'h0A4: begin // ST.B rd,rj,si12（rd=数据源，地址=rj+si12）
                alu_src=1'b1; imm_sel=3'd1; alu_op=6'd0; mem_wen=1'b1; mem_sel=3'd5; end
            12'h0A5: begin // ST.H
                alu_src=1'b1; imm_sel=3'd1; alu_op=6'd0; mem_wen=1'b1; mem_sel=3'd6; end
            12'h0A6: begin // ST.W
                alu_src=1'b1; imm_sel=3'd1; alu_op=6'd0; mem_wen=1'b1; mem_sel=3'd7; end
            12'h0A8: begin // LD.BU（零扩展字节）
                reg_we=1'b1; alu_src=1'b1; imm_sel=3'd1; alu_op=6'd0; mem_sel=3'd3; wb_sel=3'd1; end
            12'h0A9: begin // LD.HU（零扩展半字）
                reg_we=1'b1; alu_src=1'b1; imm_sel=3'd1; alu_op=6'd0; mem_sel=3'd4; wb_sel=3'd1; end
            default: ;
        endcase

        // ---------- 2RI20：LU12I.W / PCADDU12I（si20 符号扩展，ALU 内 <<12） ----------
        case (instr[31:25])
            7'h0A: begin // LU12I.W rd,si20：rd = si20 << 12
                reg_we=1'b1; alu_src=1'b1; imm_sel=3'd3; alu_op=6'd11; wb_sel=3'd0; end
            7'h0E: begin // PCADDU12I rd,si20：rd = PC + (si20 << 12)
                reg_we=1'b1; alu_src=1'b1; imm_sel=3'd3; alu_op=6'd12; wb_sel=3'd0; end
            default: ;
        endcase

        // ---------- 2RI16 / I26：分支与跳转 ----------
        case (instr[31:26])
            6'h13: begin // JIRL rd,rj,offs16：rd=PC+4，跳 rj + sext(offs16)<<2
                reg_we=1'b1; wb_sel=3'd4; jump_op=2'd3; end
            6'h14: begin // B offs26：PC = PC + sext(offs26)<<2
                jump_op=2'd1; end
            6'h15: begin // BL offs26：PC+4 写 r1（返回地址），PC = PC + sext(offs26)<<2
                reg_we=1'b1; wb_sel=3'd4; jump_op=2'd2; end
            6'h16: branch_op = 3'd1; // BEQ rj,rd,offs16：rj==rd 跳转
            6'h17: branch_op = 3'd2; // BNE
            6'h18: branch_op = 3'd3; // BLT（有符号）
            6'h19: branch_op = 3'd4; // BGE（有符号）
            6'h1A: branch_op = 3'd5; // BLTU（无符号）
            6'h1B: branch_op = 3'd6; // BGEU（无符号）
            default: ;
        endcase
    end

endmodule
