// ============================================================================
// tb_all.v —— test_all.hex（46 条全指令自检）仿真验证平台
// 装载：本文件所在运行目录下的 test_prog.hex（内容为 test_all.hex 副本，
//        imem.v 默认 $readmemh("test_prog.hex")）
// 判定：监控 MMIO 写序列
//   PASS：LED=0xFFFFFFFF → segcs=0xFFFFFFFF → seg0=0x7F → seg1=0x7F
//   FAIL：首笔 LED 写 != 0xFFFFFFFF，其低 16 位 = 组号*256 + 项号
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

    integer      nw = 0;
    reg  [31:0]  w_addr [0:15];
    reg  [31:0]  w_data [0:15];

    always @(posedge clk) begin
        if (mmio_wr && nw < 16) begin
            w_addr[nw] = mmio_addr;
            w_data[nw] = mmio_wdata;
            $display("[%0t] MMIO_WR[%0d] addr=%h data=%h", $time, nw, mmio_addr, mmio_wdata);
            nw = nw + 1;
        end
    end

    integer i;
    initial begin
        rst_n = 1'b0;
        #20 rst_n = 1'b1;
        for (i = 0; i < 450; i = i + 1) @(posedge clk);

        $display("========== MMIO 写序列（%0d 笔） ==========", nw);
        for (i = 0; i < nw; i = i + 1)
            $display("%0d: addr=%h data=%h", i, w_addr[i], w_data[i]);

        if (nw >= 4 &&
            w_data[0] == 32'hFFFFFFFF && w_data[1] == 32'hFFFFFFFF &&
            w_data[2] == 32'h0000007F && w_data[3] == 32'h0000007F)
            $display("== RESULT: PASS —— 46 条指令全部通过，LED 全亮 + 数码管 88888888 ==");
        else if (nw >= 1 && w_data[0] != 32'hFFFFFFFF && w_addr[0] == 32'hD0000000)
            $display("== RESULT: FAIL —— LED 错误码=%04h（组号=%d 项号=%d） ==",
                     w_data[0] & 16'hFFFF, (w_data[0] >> 8) & 16'hFF, w_data[0] & 16'hFF);
        else
            $display("== RESULT: UNKNOWN —— 写序列异常（nw=%0d） ==", nw);

        $display("PC = %h", pc_out);
        $finish;
    end

endmodule
