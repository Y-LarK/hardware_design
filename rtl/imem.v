// ============================================================================
// 来源：archive/single_cycle/rtl/imem.v（流水线 Step 1 复用）
// 改动：异步读改为同步读（BRAM 推断），输出寄存器即 IF/ID 的指令部分。
// ----------------------------------------------------------------------------
// imem.v —— 指令存储器（流水线版：同步读，BRAM 推断）
// ----------------------------------------------------------------------------
// 容量：4 KB = 1024 条 × 32 位（本项目只用 1/4）
//
// 时序对齐（DESIGN.md §3.5，P0 决策）：
//   pc 寄存器与 instr_r 在同一个时钟上升沿更新：
//     周期 N   ：pc = PC_N，addr = PC_N[11:2]
//     边沿 N→N+1：instr_r <= mem[PC_N[11:2]]，同时 IF/ID.pc <= PC_N
//     周期 N+1 ：instr_r = instr(PC_N)，IF/ID.pc = PC_N
//   因此 instr_r 本身就是 IF/ID 的指令寄存器，IF/ID 只再存 PC 与有效位。
//   **不要**在 IF/ID 里再存一级 instr，否则会形成
//   「BRAM 输出寄存器 + IF/ID 寄存器」两级延迟，指令与 PC 错位。
//
// 地址映射（方案 A）：复位 PC=0x1C000000，IMEM 从 0 地址开始，
//   取指地址 = pc[11:2]（忽略高 20 位）。
// ============================================================================
module imem (
    input  wire        clk,      // 时钟
    input  wire        rst_n,    // 复位（低有效，同步）
    input  wire [9:0]  addr,     // 取指地址：pc[11:2]
    output wire [31:0] instr     // 同步读出的 32 位指令（IF/ID 指令部分）
);

    // 1024 × 32 同步读 RAM（Vivado 可推断为 BRAM）
    reg [31:0] mem [0:1023];
    reg [31:0] instr_r;

    // 程序初始化：$readmemh 把十六进制机器码文件装入 IMEM
    // 文件由 sim.sh / build.tcl 通过 IMEM_FILE 宏传绝对路径
    `ifndef IMEM_FILE
    `define IMEM_FILE "test_all.hex"
    `endif
    initial $readmemh(`IMEM_FILE, mem);

    // 同步读：地址在时钟沿采样，下一拍输出数据
    always @(posedge clk) begin
        if (!rst_n)
            instr_r <= 32'd0;
        else
            instr_r <= mem[addr];
    end

    assign instr = instr_r;

endmodule
