// ============================================================================
// cpu_top.v —— 五级流水线 CPU 顶层（Step 1：骨架直通）
// ----------------------------------------------------------------------------
// 阶段划分（DESIGN.md §3.3）：
//   IF  : pc.v + imem.v（同步读，输出寄存器即 IF/ID 指令部分）
//   ID  : control.v + regfile.v + imm_ext.v -> IF/ID 只存 PC/有效位
//   EX  : alu.v -> ID/EX
//   MEM : dmem.v（同步读，读数据在 MEM 级末有效）-> EX/MEM
//   WB  : 写回寄存器堆 <- MEM/WB
//
// Step 1 范围（明确不做）：
//   - 无转发、无停顿、无冲刷：stall/flush 恒 0
//   - 分支/跳转/MUL/DIV 可译码但不保证正确；PC 每拍 +4
//   - MDU 未例化，wb_sel=2/3 暂按 ALU 结果处理（测试程序不包含乘除）
//
// 关键时序（P0，见 design/PIPELINE_IMPL.md）：
//   pc 与 imem 输出寄存器同沿更新；IF/ID 只再寄存一拍 PC，不寄存 instr。
//   dmem 的同步读地址取 EX 级 ALU 结果，与 EX/MEM 捕获地址同沿，
//   因此 MEM 级期间 mem_word 与 EX/MEM.addr 对齐，MEM/WB 在 MEM 末捕获。
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
    wire [31:0] pc;
    wire [31:0] next_pc;
    wire        stall;              // Step 1 恒 0，预留
    wire        flush;              // Step 1 恒 0，预留
    wire [31:0] imem_instr;         // IMEM 同步读输出（IF/ID 指令部分）

    // ---- IF/ID ----
    wire [31:0] ifid_pc;
    wire        ifid_valid;

    // ---- ID ----
    wire [4:0]  id_ra1, id_ra2;
    wire        id_reg_we;
    wire        id_alu_src;
    wire [2:0]  id_imm_sel;
    wire [5:0]  id_alu_op;
    wire        id_mem_wen;
    wire [2:0]  id_mem_sel;
    wire [2:0]  id_wb_sel;
    wire        id_mul_valid, id_div_valid;
    wire [1:0]  id_mul_op, id_div_op;
    wire [2:0]  id_branch_op;
    wire [1:0]  id_jump_op;
    wire        id_shift_imm;
    wire [31:0] id_rd1, id_rd2;
    wire [31:0] id_imm;
    wire [4:0]  id_shamt;
    wire [31:0] id_alu_b;
    wire [4:0]  id_dest;

    // ---- ID/EX ----
    wire        idex_valid;
    wire [31:0] idex_pc;
    wire [31:0] idex_alu_a;
    wire [31:0] idex_alu_b;
    wire [31:0] idex_store_data;
    wire [4:0]  idex_shamt;
    wire [5:0]  idex_alu_op;
    wire [4:0]  idex_dest;
    wire        idex_reg_we;
    wire        idex_mem_wen;
    wire [2:0]  idex_mem_sel;
    wire [2:0]  idex_wb_sel;

    // ---- EX ----
    wire [31:0] ex_alu_res;

    // ---- EX/MEM ----
    wire        exmem_valid;
    wire [31:0] exmem_alu_res;
    wire [31:0] exmem_store_data;
    wire [31:0] exmem_pc;
    wire [4:0]  exmem_dest;
    wire        exmem_reg_we;
    wire        exmem_mem_wen;
    wire [2:0]  exmem_mem_sel;
    wire [2:0]  exmem_wb_sel;

    // ---- MEM ----
    wire [31:0] dmem_rdata;

    // ---- MEM/WB ----
    wire        memwb_valid;
    wire [31:0] memwb_alu_res;
    wire [31:0] memwb_mem_rdata;
    wire [31:0] memwb_pc;
    wire [4:0]  memwb_dest;
    wire        memwb_reg_we;
    wire [2:0]  memwb_wb_sel;

    // ---- WB ----
    wire        wb_we;
    wire [31:0] wb_data;
    wire        mem_wen_eff;

    // ================= Step 1 预留控制 =================
    assign stall = 1'b0;
    assign flush = 1'b0;

    // ================= IF =================
    assign next_pc = pc + 32'd4;    // Step 1：顺序 +4，不处理分支/跳转

    pc u_pc (
        .clk(clk), .rst_n(rst_n), .en(~stall),
        .next_pc(next_pc), .pc(pc)
    );

    imem u_imem (
        .clk(clk), .rst_n(rst_n),
        .addr(pc[11:2]), .instr(imem_instr)
    );

    // IF/ID：只存 PC 与有效位；指令由 imem 输出寄存器直接提供
    if_id_reg u_if_id (
        .clk(clk), .rst_n(rst_n), .en(~stall), .flush(flush),
        .pc_in(pc), .valid_in(1'b1),
        .pc_out(ifid_pc), .valid_out(ifid_valid)
    );

    // ================= ID =================
    control u_control (
        .instr(imem_instr),
        .ra1(id_ra1), .ra2(id_ra2),
        .reg_we(id_reg_we), .alu_src(id_alu_src), .imm_sel(id_imm_sel),
        .alu_op(id_alu_op), .mem_wen(id_mem_wen), .mem_sel(id_mem_sel),
        .wb_sel(id_wb_sel),
        .mul_valid(id_mul_valid), .div_valid(id_div_valid),
        .mul_op(id_mul_op), .div_op(id_div_op),
        .branch_op(id_branch_op), .jump_op(id_jump_op),
        .shift_imm(id_shift_imm)
    );

    regfile u_regfile (
        .clk(clk), .we(wb_we),
        .ra1(id_ra1), .ra2(id_ra2),
        .wa(memwb_dest), .wd(wb_data),
        .rd1(id_rd1), .rd2(id_rd2)
    );

    imm_ext u_imm (
        .instr(imem_instr), .imm_sel(id_imm_sel), .imm_out(id_imm)
    );

    // 移位量：立即数移位取 instr[14:10]，寄存器移位取 rd2[4:0]
    assign id_shamt  = id_shift_imm ? imem_instr[14:10] : id_rd2[4:0];
    // ALU B 源：立即数或寄存器 rd2
    assign id_alu_b  = id_alu_src ? id_imm : id_rd2;
    // 写回地址：BL 隐含写 r1，其余写 rd（instr[4:0]）
    assign id_dest   = (id_jump_op == 2'd2) ? 5'd1 : imem_instr[4:0];

    id_ex_reg u_id_ex (
        .clk(clk), .rst_n(rst_n), .en(~stall), .flush(flush),
        .valid_in(ifid_valid),
        .pc_in(ifid_pc),
        .alu_a_in(id_rd1),
        .alu_b_in(id_alu_b),
        .store_data_in(id_rd2),
        .shamt_in(id_shamt),
        .alu_op_in(id_alu_op),
        .dest_in(id_dest),
        .reg_we_in(id_reg_we),
        .mem_wen_in(id_mem_wen),
        .mem_sel_in(id_mem_sel),
        .wb_sel_in(id_wb_sel),
        .valid_out(idex_valid),
        .pc_out(idex_pc),
        .alu_a_out(idex_alu_a),
        .alu_b_out(idex_alu_b),
        .store_data_out(idex_store_data),
        .shamt_out(idex_shamt),
        .alu_op_out(idex_alu_op),
        .dest_out(idex_dest),
        .reg_we_out(idex_reg_we),
        .mem_wen_out(idex_mem_wen),
        .mem_sel_out(idex_mem_sel),
        .wb_sel_out(idex_wb_sel)
    );

    // ================= EX =================
    alu u_alu (
        .a(idex_alu_a), .b(idex_alu_b), .pc(idex_pc),
        .shamt(idex_shamt), .alu_op(idex_alu_op),
        .result(ex_alu_res)
    );

    ex_mem_reg u_ex_mem (
        .clk(clk), .rst_n(rst_n), .en(~stall), .flush(flush),
        .valid_in(idex_valid),
        .alu_res_in(ex_alu_res),
        .store_data_in(idex_store_data),
        .pc_in(idex_pc),
        .dest_in(idex_dest),
        .reg_we_in(idex_reg_we),
        .mem_wen_in(idex_mem_wen),
        .mem_sel_in(idex_mem_sel),
        .wb_sel_in(idex_wb_sel),
        .valid_out(exmem_valid),
        .alu_res_out(exmem_alu_res),
        .store_data_out(exmem_store_data),
        .pc_out(exmem_pc),
        .dest_out(exmem_dest),
        .reg_we_out(exmem_reg_we),
        .mem_wen_out(exmem_mem_wen),
        .mem_sel_out(exmem_mem_sel),
        .wb_sel_out(exmem_wb_sel)
    );

    // ================= MEM =================
    // DMEM 同步读地址取 EX 级 ALU 结果（与 EX/MEM 捕获地址同沿）；
    // 写 / MMIO / 宽度选择用 MEM 级（EX/MEM）信号。
    assign mem_wen_eff = exmem_valid && exmem_mem_wen;

    dmem u_dmem (
        .clk(clk), .rst_n(rst_n),
        .raddr(ex_alu_res),
        .addr(exmem_alu_res),
        .wdata(exmem_store_data),
        .mem_wen(mem_wen_eff),
        .mem_sel(exmem_mem_sel),
        .mmio_rdata(mmio_rdata),
        .rdata(dmem_rdata),
        .mmio_wr(mmio_wr),
        .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),
        .mmio_sel_out(mmio_sel)
    );

    mem_wb_reg u_mem_wb (
        .clk(clk), .rst_n(rst_n), .en(~stall), .flush(flush),
        .valid_in(exmem_valid),
        .alu_res_in(exmem_alu_res),
        .mem_rdata_in(dmem_rdata),
        .pc_in(exmem_pc),
        .dest_in(exmem_dest),
        .reg_we_in(exmem_reg_we),
        .wb_sel_in(exmem_wb_sel),
        .valid_out(memwb_valid),
        .alu_res_out(memwb_alu_res),
        .mem_rdata_out(memwb_mem_rdata),
        .pc_out(memwb_pc),
        .dest_out(memwb_dest),
        .reg_we_out(memwb_reg_we),
        .wb_sel_out(memwb_wb_sel)
    );

    // ================= WB =================
    // 写回数据源：0=ALU 1=DMEM 4=PC+4；2/3（MDU）Step 1 未实现
    reg [31:0] wb_data_r;
    always @(*) begin
        case (memwb_wb_sel)
            3'd1:    wb_data_r = memwb_mem_rdata;
            3'd4:    wb_data_r = memwb_pc + 32'd4;
            default: wb_data_r = memwb_alu_res;
        endcase
    end

    assign wb_data = wb_data_r;
    assign wb_we   = memwb_valid && memwb_reg_we;

    // ================= 观测输出 =================
    assign pc_out = pc;
    assign reg_we = wb_we;
    assign reg_wa = memwb_dest;
    assign reg_wd = wb_data;

endmodule
