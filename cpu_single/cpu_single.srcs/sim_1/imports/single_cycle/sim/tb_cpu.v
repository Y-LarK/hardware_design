// ============================================================================
// tb_cpu.v —— 单周期 CPU 顶层测试平台
// ----------------------------------------------------------------------------
// 流程：
//   1. 复位拉低若干拍，再拉高（同步复位，CPU 从 0x1C000000 开始取指）
//   2. 每拍监测写回事件：$display 打印 (PC, 目的寄存器, 写回值)
//   3. 跑满 N 拍后，层次引用读出寄存器堆终值并打印，供与期望表比对
// 期望（test_prog.hex，地址 0x1C000000 起）：
//   r1=0x1C000048 r2=3 r3=13 r4=7 r5=10 r6=0x10A r7=40 r8=30
//   r9=3 r10=1 r11=5 r12=13 r13=9 r14=0x1C000058，Mem[4]=13
// ============================================================================
`timescale 1ns/1ps

module tb_cpu;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    wire [31:0] pc_out;
    wire        reg_we;
    wire [4:0]  reg_wa;
    wire [31:0] reg_wd;

    // ---- CPU 例化（MMIO 悬空，仿真用不到外设） ----
    cpu_top u_cpu (
        .clk(clk), .rst_n(rst_n),
        .pc_out(pc_out), .reg_we(reg_we), .reg_wa(reg_wa), .reg_wd(reg_wd),
        .mmio_wr(), .mmio_addr(), .mmio_wdata(), .mmio_sel(),
        .mmio_rdata(32'd0)
    );

    always #5 clk = ~clk;   // 100 MHz 时钟

    integer i;

    // ---- 写回事件监测 ----
    always @(posedge clk) begin
        if (reg_we && reg_wa != 5'd0)
            $display("[%0t] PC=%h  WR r%-2d = %h", $time, pc_out, reg_wa, reg_wd);
    end

    initial begin
        // 复位：同步复位，低有效
        rst_n = 1'b0;
        #20 rst_n = 1'b1;

        // 跑 60 个周期（程序约 25 拍到达 halt 自循环，余量充足）
        for (i = 0; i < 60; i = i + 1) @(posedge clk);

        // 终值检查（层次引用寄存器堆）
        $display("========== FINAL REGISTERS ==========");
        for (i = 0; i < 32; i = i + 1)
            $display("r%-2d = %h", i, u_cpu.u_regfile.regs[i]);
        $display("Mem[4] = %h", u_cpu.u_dmem.mem[1]);   // 地址 4 -> 索引 1
        $display("========== SIM DONE ==========");
        $finish;
    end

endmodule
