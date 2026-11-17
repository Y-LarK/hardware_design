// ============================================================================
// tb_pipeline.v —— 流水线 Step 1「骨架直通」批处理仿真平台
// ----------------------------------------------------------------------------
// 装载：IMEM_FILE 宏指定的 hex（由 scripts/sim.sh 传入绝对路径）
//
// 判定分两部分，任一不符即 FAIL：
//   (1) CPU MMIO 写序列：按流水线时序采样 mmio_wr（MEM 级有效，posedge 采样），
//       与 expected 表逐笔、按顺序比对全部 30 笔，而不是只看最后 4 笔。
//       test_pipe_basic.s 每一条计算指令的结果都先写到 LED，最后才是 4 笔
//       PASS 序列：
//         [ 0.. 6] addi.w / lu12i.w / ori 常量初始化结果
//         [ 7..25] 19 条计算指令结果（含 pcaddu12i）
//         [26] LED       <- 0xFFFFFFFF
//         [27] seg_cs    <- 0xFFFFFFFF
//         [28] seg_data0 <- 0x7F
//         [29] seg_data1 <- 0x7F
//       数据全部由 ALU 结果产生，序列中任一值不符即说明对应 ALU 操作、
//       译码或流水对齐出错。
//   (2) DMEM 字节/半字写语义：Step 1 的 CPU 程序只写 MMIO、不访问 DMEM，
//       故上面的序列覆盖不到 dmem.v 的写通道。这里用独立 dmem 实例直接
//       验证 ST.B/ST.H/ST.W 的字节使能、小端对齐、LD.B/LD.BU/LD.H/LD.HU
//       符号/零扩展，以及 MMIO 地址不写 RAM。dmem 写通道被改错时本项 FAIL。
//
// 运行长度：程序 56 条 + 256 条安全填充 + DMEM 单元测试约 20 拍，
//           等待 140 拍足以覆盖最后一条写并避免取到填充之外的 IMEM 字。
// ============================================================================

module tb_pipeline;

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

    // ===================== (1) CPU MMIO 写序列采样 =====================
    integer     nw = 0;
    reg  [31:0] w_addr [0:31];
    reg  [31:0] w_data [0:31];

    // 期望写序列（30 笔），来源指令见 test_pipe_basic.s 的注释
    reg  [31:0] exp_addr [0:29];
    reg  [31:0] exp_data [0:29];

    always @(posedge clk) begin
        if (mmio_wr) begin
            if (nw < 32) begin
                w_addr[nw] = mmio_addr;
                w_data[nw] = mmio_wdata;
            end
            $display("[%0t] MMIO_WR[%0d] addr=%h data=%h sel=%0d",
                     $time, nw, mmio_addr, mmio_wdata, mmio_sel);
            nw = nw + 1;
        end
    end

    // ===================== (2) DMEM 单元测试实例 =====================
    // 与 CPU 共用 clk / rst_n，其余信号由 tb 独立驱动，互不干扰。
    reg         d_wen;
    reg  [2:0]  d_sel;
    reg  [31:0] d_raddr;
    reg  [31:0] d_addr;
    reg  [31:0] d_wdata;
    wire [31:0] d_rdata;
    wire        d_mmio_wr;
    wire [31:0] d_mmio_addr;
    wire [31:0] d_mmio_wdata;
    wire [2:0]  d_mmio_sel;

    dmem u_dmem_tb (
        .clk(clk), .rst_n(rst_n),
        .raddr(d_raddr), .addr(d_addr), .wdata(d_wdata),
        .mem_wen(d_wen), .mem_sel(d_sel), .mmio_rdata(32'd0),
        .rdata(d_rdata),
        .mmio_wr(d_mmio_wr), .mmio_addr(d_mmio_addr),
        .mmio_wdata(d_mmio_wdata), .mmio_sel_out(d_mmio_sel)
    );

    reg         dmem_ok;

    // 写一拍（在 negedge 建立输入，posedge 完成写入）
    task dmem_wr;
        input [31:0] a;
        input [31:0] d;
        input [2:0]  s;
        begin
            @(negedge clk);
            d_raddr = a; d_addr = a; d_wdata = d; d_sel = s; d_wen = 1'b1;
            @(negedge clk);          // 中间的一个 posedge 完成写入
            d_wen = 1'b0;
        end
    endtask

    // 读一拍并比对：raddr 在 posedge 被同步读采样，再等一个 negedge 后
    // mem_word 与 addr/mem_sel 同拍，rdata 即为该地址的（扩展后）数据。
    task dmem_rd;
        input [31:0] a;
        input [2:0]  s;
        input [31:0] exp;
        begin
            @(negedge clk);
            d_raddr = a; d_addr = a; d_sel = s; d_wen = 1'b0;
            @(negedge clk);
            if (d_rdata !== exp) begin
                $display("DMEM FAIL: addr=%h sel=%0d exp=%h got=%h",
                         a, s, exp, d_rdata);
                dmem_ok = 1'b0;
            end
        end
    endtask

    // MMIO 地址写：必须产生 mmio_wr 脉冲，且不得写 RAM
    task dmem_mmio_wr;
        input [31:0] a;
        input [31:0] d;
        input [2:0]  s;
        begin
            @(negedge clk);
            d_raddr = a; d_addr = a; d_wdata = d; d_sel = s; d_wen = 1'b1;
            #1;
            if (d_mmio_wr !== 1'b1 ||
                d_mmio_addr !== a || d_mmio_wdata !== d || d_mmio_sel !== s) begin
                $display("DMEM FAIL: MMIO 写接口不符 addr=%h data=%h sel=%0d (wr=%b)",
                         a, d, s, d_mmio_wr);
                dmem_ok = 1'b0;
            end
            @(negedge clk);
            d_wen = 1'b0;
        end
    endtask

    // ===================== 主流程 =====================
    integer     i;
    reg         cpu_ok;

    initial begin
        // ---- 期望写序列（与 test_pipe_basic.s 的 store 顺序一一对应） ----
        exp_addr[0]  = 32'hD0000000; exp_data[0]  = 32'h0000000A; // addi.w  $r4  10
        exp_addr[1]  = 32'hD0000000; exp_data[1]  = 32'h00000003; // addi.w  $r5  3
        exp_addr[2]  = 32'hD0000000; exp_data[2]  = 32'hFFFFFFFF; // addi.w  $r6  -1
        exp_addr[3]  = 32'hD0000000; exp_data[3]  = 32'h12345000; // lu12i.w $r7
        exp_addr[4]  = 32'hD0000000; exp_data[4]  = 32'h00000F0F; // ori     $r8
        exp_addr[5]  = 32'hD0000000; exp_data[5]  = 32'h000000FF; // ori     $r9
        exp_addr[6]  = 32'hD0000000; exp_data[6]  = 32'hD0000000; // lu12i.w $r10
        exp_addr[7]  = 32'hD0000000; exp_data[7]  = 32'h0000000D; // add.w
        exp_addr[8]  = 32'hD0000000; exp_data[8]  = 32'hFFFFFFF9; // sub.w
        exp_addr[9]  = 32'hD0000000; exp_data[9]  = 32'h00000003; // addi.w -7
        exp_addr[10] = 32'hD0000000; exp_data[10] = 32'h0000000F; // and
        exp_addr[11] = 32'hD0000000; exp_data[11] = 32'h00000FFF; // or
        exp_addr[12] = 32'hD0000000; exp_data[12] = 32'hFFFFF000; // nor
        exp_addr[13] = 32'hD0000000; exp_data[13] = 32'h00000FF0; // xor
        exp_addr[14] = 32'hD0000000; exp_data[14] = 32'h00000050; // sll.w
        exp_addr[15] = 32'hD0000000; exp_data[15] = 32'h1FFFFFFF; // srl.w
        exp_addr[16] = 32'hD0000000; exp_data[16] = 32'hFFFFFFFF; // sra.w
        exp_addr[17] = 32'hD0000000; exp_data[17] = 32'h00000001; // slt
        exp_addr[18] = 32'hD0000000; exp_data[18] = 32'h00000000; // sltu
        exp_addr[19] = 32'hD0000000; exp_data[19] = 32'h0000000F; // andi
        exp_addr[20] = 32'hD0000000; exp_data[20] = 32'h000000F0; // xori
        exp_addr[21] = 32'hD0000000; exp_data[21] = 32'h000000A0; // slli.w
        exp_addr[22] = 32'hD0000000; exp_data[22] = 32'h0000000F; // srli.w
        exp_addr[23] = 32'hD0000000; exp_data[23] = 32'h0000007F; // ori
        exp_addr[24] = 32'hD0000000; exp_data[24] = 32'hFFFFFFFF; // srai.w
        exp_addr[25] = 32'hD0000000; exp_data[25] = 32'h1C001064; // pcaddu12i
        exp_addr[26] = 32'hD0000000; exp_data[26] = 32'hFFFFFFFF; // LED
        exp_addr[27] = 32'hD000000C; exp_data[27] = 32'hFFFFFFFF; // seg_cs
        exp_addr[28] = 32'hD0000004; exp_data[28] = 32'h0000007F; // seg_data0
        exp_addr[29] = 32'hD0000008; exp_data[29] = 32'h0000007F; // seg_data1

        rst_n = 1'b0;
        dmem_ok = 1'b1;
        d_wen = 1'b0; d_sel = 3'd0;
        d_raddr = 32'd0; d_addr = 32'd0; d_wdata = 32'd0;
        #20 rst_n = 1'b1;

        // ---------------------------------------------------------------
        // DMEM 单元测试（与 CPU 并行）
        //   基准字 0xAABBCCDD 的小端字节布局：byte0=DD byte1=CC byte2=BB byte3=AA
        // ---------------------------------------------------------------
        dmem_wr(32'h0000_0000, 32'hAABB_CCDD, 3'd7);   // ST.W
        dmem_rd(32'h0000_0000, 3'd2, 32'hAABB_CCDD);   // LD.W

        // ST.B 偏移 2（byte2）：写 0x11 -> 0xAA11CCDD
        dmem_wr(32'h0000_0002, 32'h0000_0011, 3'd5);
        dmem_rd(32'h0000_0000, 3'd2, 32'hAA11_CCDD);
        dmem_rd(32'h0000_0002, 3'd0, 32'h0000_0011);   // LD.B 正数

        // ST.B 偏移 3（byte3）：写 0x80 -> 验证符号扩展 / 零扩展差异
        dmem_wr(32'h0000_0003, 32'h0000_0080, 3'd5);
        dmem_rd(32'h0000_0003, 3'd0, 32'hFFFF_FF80);   // LD.B（符号扩展）
        dmem_rd(32'h0000_0003, 3'd3, 32'h0000_0080);   // LD.BU（零扩展）

        // ST.H 偏移 0：写 0x1234 -> 0x80111234
        dmem_wr(32'h0000_0000, 32'h0000_1234, 3'd6);
        dmem_rd(32'h0000_0000, 3'd2, 32'h8011_1234);   // LD.W
        dmem_rd(32'h0000_0000, 3'd1, 32'h0000_1234);   // LD.H

        // ST.H 偏移 2：写 0x5678 -> 0x56781234
        dmem_wr(32'h0000_0002, 32'h0000_5678, 3'd6);
        dmem_rd(32'h0000_0002, 3'd1, 32'h0000_5678);   // LD.H
        dmem_rd(32'h0000_0000, 3'd2, 32'h5678_1234);   // LD.W
        dmem_rd(32'h0000_0002, 3'd4, 32'h0000_5678);   // LD.HU

        // ST.B 偏移 1（byte1）：写 0xFF -> 0x5678FF34，LD.B 负数
        dmem_wr(32'h0000_0001, 32'h0000_00FF, 3'd5);
        dmem_rd(32'h0000_0001, 3'd0, 32'hFFFF_FFFF);   // LD.B（符号扩展）
        dmem_rd(32'h0000_0000, 3'd2, 32'h5678_FF34);   // LD.W

        // MMIO 地址写：必须产生 mmio_wr 脉冲，且不写 RAM
        dmem_mmio_wr(32'hD000_0000, 32'hDEAD_BEEF, 3'd7);
        dmem_rd(32'h0000_0000, 3'd2, 32'h5678_FF34);   // RAM 未被改动

        if (dmem_ok)
            $display("DMEM: 单元测试通过（ST.B/ST.H/ST.W 字节使能、符号扩展、MMIO 屏蔽）");

        // 等 CPU 测试程序跑完
        cpu_ok = 1'b1;
        for (i = 0; i < 140; i = i + 1) @(posedge clk);

        $display("========== MMIO 写序列（%0d 笔，期望 30 笔） ==========", nw);
        for (i = 0; i < nw && i < 32; i = i + 1)
            $display("%0d: addr=%h data=%h", i, w_addr[i], w_data[i]);

        if (nw != 30) begin
            $display("MMIO 笔数不符：期望 30，实际 %0d", nw);
            cpu_ok = 1'b0;
        end
        for (i = 0; i < 30; i = i + 1) begin
            if (w_addr[i] !== exp_addr[i] || w_data[i] !== exp_data[i]) begin
                $display("MISMATCH[%0d]: exp addr=%h data=%h, got addr=%h data=%h",
                         i, exp_addr[i], exp_data[i], w_addr[i], w_data[i]);
                cpu_ok = 1'b0;
            end
        end

        if (cpu_ok && dmem_ok)
            $display("== RESULT: PASS —— 流水线 MMIO 序列与 DMEM 语义均正确 ==");
        else
            $display("== RESULT: FAIL —— cpu_ok=%0d dmem_ok=%0d (nw=%0d) ==",
                     cpu_ok, dmem_ok, nw);

        $display("PC = %h", pc_out);
        $finish;
    end

endmodule
