// ============================================================================
// tb_all.v —— test_all.hex（全指令自检）仿真验证平台
// 装载：IMEM_FILE 宏指定的 hex（综合与批处理仿真共用，见 build.tcl/sim.sh）
// 判定：监控 MMIO 写序列（进度灯写也在其中）
//   PASS：最后四笔为 LED=0xFFFFFFFF → segcs=0xFFFFFFFF → seg0=0x7F → seg1=0x7F
//   FAIL：最后一笔 LED 写 != 0xFFFFFFFF，其低 16 位 = 组号*256 + 项号
// ============================================================================

module tb_all;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    wire [31:0] pc_out;
    wire        reg_we;
    wire [4:0]  reg_wa;
    wire [31:0] reg_wd;
    wire        mmio_wr;
    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire [2:0]  mmio_sel;

    cpu_top u_cpu (
        .clk(clk), .rst_n(rst_n),
        .pc_out(pc_out), .reg_we(reg_we), .reg_wa(reg_wa), .reg_wd(reg_wd),
        .mmio_wr(mmio_wr), .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_sel(mmio_sel), .mmio_rdata(32'd0)
    );

    always #5 clk = ~clk;   // 100 MHz

    // 环形缓冲：容量按最坏情况（全部指令通过，写序列最长）取 64 笔
    integer      nw = 0;
    reg  [31:0]  w_addr [0:63];
    reg  [31:0]  w_data [0:63];

    always @(posedge clk) begin
        if (mmio_wr) begin
            w_addr[nw % 64] = mmio_addr;
            w_data[nw % 64] = mmio_wdata;
            $display("[%0t] MMIO_WR[%0d] addr=%h data=%h", $time, nw, mmio_addr, mmio_wdata);
            nw = nw + 1;
        end
    end

    integer i;
    initial begin
        rst_n = 1'b0;
        #20 rst_n = 1'b1;
        // 周期预算：测试程序含 8 段 125ms 软件延迟（每段约 6.3 万拍，共约 50 万拍），
        // 再留一倍余量；xsim 跑完约 1 分钟
        for (i = 0; i < 1200000; i = i + 1) @(posedge clk);

        $display("========== MMIO 写序列（%0d 笔） ==========", nw);
        for (i = 0; i < nw && i < 64; i = i + 1)
            $display("%0d: addr=%h data=%h", i, w_addr[i], w_data[i]);

        // FAIL 路径固定写序（共 5 笔）：
        //   LED错误码 -> seg_data0(组号) -> seg_cs=0x01 -> seg_data1(项号) -> seg_cs=0x11
        // 因此最后一笔是 seg_cs=0x11，LED 错误码在倒数第 5 笔
        if (nw >= 4 &&
            w_data[(nw-4) % 64] == 32'hFFFFFFFF && w_data[(nw-3) % 64] == 32'hFFFFFFFF &&
            w_data[(nw-2) % 64] == 32'h0000007F && w_data[(nw-1) % 64] == 32'h0000007F)
            $display("== RESULT: PASS —— 全部指令通过，LED 全亮 + 数码管 88888888 ==");
        else if (nw >= 5 &&
                 w_addr[(nw-1) % 64] == 32'hD000000C && w_data[(nw-1) % 64] == 32'h11 &&
                 w_addr[(nw-5) % 64] == 32'hD0000000 && w_data[(nw-5) % 64] != 32'hFFFFFFFF)
            $display("== RESULT: FAIL —— LED 错误码=%04h（组号=%0d 项号=%0d） ==",
                     w_data[(nw-5) % 64] & 16'hFFFF,
                     (w_data[(nw-5) % 64] >> 8) & 16'hFF, w_data[(nw-5) % 64] & 16'hFF);
        else
            $display("== RESULT: UNKNOWN —— 写序列异常（nw=%0d） ==", nw);

        $display("PC = %h", pc_out);
        $finish;
    end

endmodule
