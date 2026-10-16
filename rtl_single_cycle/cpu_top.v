// ============================================================================
// cpu_top.v —— 单周期 CPU 顶层（数据通路 + 控制 + 存储器）
// ----------------------------------------------------------------------------
// 结构（对应课件《指令处理的数据通路》经典单周期图，LA32R 版）：
//   PC -> IMEM -> 译码(control/imm_ext) -> 寄存器堆 -> ALU/MDU -> DMEM -> 写回
//   PC 更新：pc+4 / 分支目标 pc+sext(offs16)<<2 / 跳转目标（I26 或 JIRL）
// 关键实现口径（DESIGN.md）：
//   - 分支偏移基准 = 本条指令 PC（不是 PC+4）
//   - 分支比较 rj vs rd（2RI16 汇编格式：BEQ rj, rd, offs16）
//   - JIRL 目标 = GR[rj] + sext(offs16)<<2，PC+4 写 rd
//   - BL 把 PC+4 写 r1
//   - 寄存器堆 2 读 1 写 + 同拍旁路（模块内）
//   - IMEM/DMEM 用分布式 RAM（异步读，单周期时序要求）
//   - 访存地址高 4 位 == 0xD 时路由 MMIO（外设）
// ============================================================================
module cpu_top (
    input  wire        clk,
    input  wire        rst_n,
    // ---- 观测端口（仿真/调试用；上板顶层悬空不接） ----
    output wire [31:0] pc_out,     // 当前 PC
    output wire        reg_we,     // 寄存器写使能（观测）
    output wire [4:0]  reg_wa,     // 寄存器写地址（观测）
    output wire [31:0] reg_wd,     // 寄存器写数据（观测）
    // ---- MMIO 接口（上板顶层例化外设寄存器） ----
    output wire        mmio_wr,
    output wire [31:0] mmio_addr,
    output wire [31:0] mmio_wdata,
    output wire [2:0]  mmio_sel,
    input  wire [31:0] mmio_rdata
);

    // ================= 内部连线 =================
    wire [31:0] pc, next_pc;
    wire [31:0] instr;
    wire [31:0] rd1, rd2;                 // 寄存器堆读数据
    wire [31:0] imm_out;                  // 扩展后立即数
    wire [31:0] alu_res;                  // ALU 结果
    wire [31:0] mul_res, div_res;         // 乘除结果
    wire [31:0] mem_rdata;                // 访存读数据（含 MMIO）
    wire [31:0] pc_plus4 = pc + 32'd4;

    // 控制信号
    wire [4:0]  ra1, ra2, wa;
    wire        alu_src;
    wire [2:0]  imm_sel;
    wire [5:0]  alu_op;
    wire        mem_wen;
    wire [2:0]  mem_sel;
    wire [2:0]  wb_sel;
    wire        mul_valid, div_valid;
    wire [1:0]  mul_op, div_op;
    wire [2:0]  branch_op;
    wire [1:0]  jump_op;
    wire        shift_imm;
    wire        mmio_sel_flag;   // 访存地址是否落在 MMIO 段
    reg         branch_taken;
    wire        jump_active;

    // ================= 模块例化 =================
    // PC：单周期恒使能
    pc u_pc (.clk(clk), .rst_n(rst_n), .en(1'b1), .next_pc(next_pc), .pc(pc));

    // 指令存储器：地址取 pc[11:2]，把 0x1C000000 起始空间映射到 RAM 0 地址
    imem u_imem (.addr(pc[11:2]), .instr(instr));

    // 译码
    control u_control (
        .instr(instr), .ra1(ra1), .ra2(ra2), .reg_we(reg_we), .alu_src(alu_src),
        .imm_sel(imm_sel), .alu_op(alu_op), .mem_wen(mem_wen), .mem_sel(mem_sel),
        .wb_sel(wb_sel), .mul_valid(mul_valid), .div_valid(div_valid),
        .mul_op(mul_op), .div_op(div_op), .branch_op(branch_op),
        .jump_op(jump_op), .shift_imm(shift_imm)
    );

    // 寄存器堆（2 读 1 写 + 同拍旁路）
    regfile u_regfile (.clk(clk), .we(reg_we), .ra1(ra1), .ra2(ra2),
                       .wa(wa), .wd(reg_wd), .rd1(rd1), .rd2(rd2));

    // 立即数扩展
    imm_ext u_imm (.instr(instr), .imm_sel(imm_sel), .imm_out(imm_out));

    // ALU：A=rd1(rj)，B=立即数或 rd2(rk)；移位量按 shift_imm 选择
    wire [4:0] shamt = shift_imm ? instr[14:10] : rd2[4:0];
    alu u_alu (.a(rd1), .b(alu_src ? imm_out : rd2), .pc(pc), .shamt(shamt),
               .alu_op(alu_op), .result(alu_res));

    // 组合乘除单元
    mdu u_mdu (.a(rd1), .b(rd2), .mul_op(mul_op), .div_op(div_op),
               .mul_valid(mul_valid), .div_valid(div_valid),
               .mul_res(mul_res), .div_res(div_res));

    // 数据存储器 + MMIO 译码（地址高 4 位 == 0xD）
    assign mmio_sel_flag = (alu_res[31:28] == 4'hD);
    dmem u_dmem (.clk(clk), .addr(alu_res), .wdata(rd2), .mem_wen(mem_wen),
                 .mem_sel(mem_sel), .mmio_sel(mmio_sel_flag), .mmio_rdata(mmio_rdata),
                 .rdata(mem_rdata), .mmio_wr(mmio_wr), .mmio_addr(mmio_addr),
                 .mmio_wdata(mmio_wdata), .mmio_sel_out(mmio_sel));

    // ================= 分支 / 跳转 / 下一 PC =================
    wire [15:0] offs16 = instr[25:10];   // 2RI16 偏移
    wire [25:0] offs26 = {instr[9:0], instr[25:10]};    // I26 偏移

    // 分支目标：pc + sext(offs16) << 2（基准 = 本条指令 PC，不是 PC+4！）
    wire [31:0] branch_target = pc + {{14{offs16[15]}}, offs16, 2'b00};
    // 无条件跳转目标：I26 目标 = PC + sext(offs26)<<2；JIRL 目标 = GR[rj] + sext(offs16)<<2
    wire [31:0] jump_target_i26  = pc  + {{4{offs26[25]}}, offs26, 2'b00};
    wire [31:0] jump_target_jirl = rd1 + {{14{offs16[15]}}, offs16, 2'b00};

    // 分支比较（rj vs rd；有符号/无符号两套）
    wire beq_t  = (rd1 == rd2);
    wire bne_t  = (rd1 != rd2);
    wire blt_t  = ($signed(rd1) <  $signed(rd2));
    wire bge_t  = ($signed(rd1) >= $signed(rd2));
    wire bltu_t = (rd1 < rd2);
    wire bgeu_t = (rd1 >= rd2);

    always @(*) begin
        case (branch_op)
            3'd1: branch_taken = beq_t;
            3'd2: branch_taken = bne_t;
            3'd3: branch_taken = blt_t;
            3'd4: branch_taken = bge_t;
            3'd5: branch_taken = bltu_t;
            3'd6: branch_taken = bgeu_t;
            default: branch_taken = 1'b0;
        endcase
    end

    assign jump_active = (jump_op != 2'd0);
    assign next_pc = jump_active ? (jump_op == 2'd3 ? jump_target_jirl : jump_target_i26)
                                 : (branch_taken ? branch_target : pc_plus4);

    // ================= 写回 =================
    // 写回数据源：ALU / 访存 / 乘法 / 除法 / PC+4（BL、JIRL）
    reg [31:0] wb_data;
    always @(*) begin
        case (wb_sel)
            3'd1: wb_data = mem_rdata;
            3'd2: wb_data = mul_res;
            3'd3: wb_data = div_res;
            3'd4: wb_data = pc_plus4;   // BL / JIRL 的链接值
            default: wb_data = alu_res;
        endcase
    end

    // 写回地址：BL 隐含写 r1（返回地址寄存器），其余指令写 rd
    assign wa = (jump_op == 2'd2) ? 5'd1 : instr[4:0];

    // 观测输出
    assign pc_out = pc;
    assign reg_wa = wa;
    assign reg_wd = wb_data;

endmodule
