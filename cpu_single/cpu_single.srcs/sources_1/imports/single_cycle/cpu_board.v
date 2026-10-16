// ============================================================================
// cpu_board.v —— 上板顶层（EGO1）：CPU + MMIO 外设寄存器 + 引脚
// ----------------------------------------------------------------------------
// 端口与引脚对应（XDC 约束见 constraints/cpu.xdc）：
//   sys_clk_in    P17  100 MHz 晶振
//   sys_rst_n     P15  复位按键（极性待上板实测，先按低有效；若相反改一行取反）
//   led_pin[15:0]      16 个 LED（高电平点亮）
//   seg_cs_pin / seg_data_0_pin / seg_data_1_pin  数码管（共阴、位选段选高有效）
//   sw_pin[7:0] / dip_pin[7:0] / btn_pin[4:0]     拨码开关与按键
// MMIO 映射（DESIGN.md §4.2）：
//   0xD0000000 W led[15:0]        0xD0000004 W seg_data0[7:0]
//   0xD0000008 W seg_data1[7:0]   0xD000000C W seg_cs[7:0]
//   0xD0000010 R {dip_pin,sw_pin} 0xD0000014 R btn_pin[4:0]
// ============================================================================
module cpu_board (
    input  wire        sys_clk_in,
    input  wire        sys_rst_n,
    output wire [15:0] led_pin,
    output wire [7:0]  seg_cs_pin,
    output wire [7:0]  seg_data_0_pin,
    output wire [7:0]  seg_data_1_pin,
    input  wire [7:0]  sw_pin,
    input  wire [7:0]  dip_pin,
    input  wire [4:0]  btn_pin
);

    // ---- 可配置分频器 ----
    // 单周期 CPU 的组合除法器路径延迟约 570 ns（综合时序实测），无法在 100 MHz
    // 下收敛。因此上板时钟可配置：
    //   CLK_DIV = 1   -> 100 MHz 直连（跑不含除法的演示程序）
    //   CLK_DIV = N   -> 100/N MHz（跑含 MUL/DIV 的全指令自检程序，如 N=100 -> 1 MHz）
    parameter CLK_DIV = 1;

    reg [15:0] clk_cnt;
    reg        cpu_clk;
    always @(posedge sys_clk_in) begin
        if (CLK_DIV == 1) begin
            clk_cnt <= 16'd0;
            cpu_clk  <= 1'b1;          // 直连（恒高，下面用 sys_clk_in）
        end else begin
            if (clk_cnt == CLK_DIV[15:0] - 16'd1) begin
                clk_cnt <= 16'd0;
                cpu_clk  <= ~cpu_clk;   // 二分频：周期 = 2*CLK_DIV 个 100MHz 周期
            end else begin
                clk_cnt <= clk_cnt + 16'd1;
            end
        end
    end
    // 实际驱动 CPU 的时钟：分频模式下用 cpu_clk，直连模式用 sys_clk_in
    wire cpu_clk_out = (CLK_DIV == 1) ? sys_clk_in : cpu_clk;

    // ---- 复位同步：输入引脚先过两级同步器，内部统一同步复位 ----
    reg rst_n_s1, rst_n_s2;
    always @(posedge cpu_clk_out) begin
        rst_n_s1 <= sys_rst_n;      // 按键极性待实测：若按下为高电平，改为 ~sys_rst_n
        rst_n_s2 <= rst_n_s1;
    end
    wire rst_n = rst_n_s2;

    // ---- MMIO 接口 ----
    wire        mmio_wr;
    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire [2:0]  mmio_sel;
    wire [31:0] mmio_rdata;

    // ---- 外设寄存器 ----
    reg [15:0] led_r;
    reg [7:0]  seg0_r, seg1_r, segcs_r;

    always @(posedge cpu_clk_out) begin
        if (!rst_n) begin
            led_r   <= 16'd0;
            seg0_r  <= 8'd0;
            seg1_r  <= 8'd0;
            segcs_r <= 8'd0;
        end else if (mmio_wr) begin
            // 按地址低 5 位译码（0xD0000000 / 04 / 08 / 0C）
            case (mmio_addr[4:2])
                3'd0: led_r   <= mmio_wdata[15:0];   // 0xD0000000：LED
                3'd1: seg0_r  <= mmio_wdata[7:0];    // 0xD0000004：数码管 0 段选
                3'd2: seg1_r  <= mmio_wdata[7:0];    // 0xD0000008：数码管 1 段选
                3'd3: segcs_r <= mmio_wdata[7:0];    // 0xD000000C：数码管位选
                default: ;
            endcase
        end
    end

    // ---- MMIO 读译码 ----
    assign mmio_rdata = (mmio_addr[4:2] == 3'd4) ? {dip_pin, sw_pin} :   // 0xD0000010：拨码开关
                        (mmio_addr[4:2] == 3'd5) ? {27'd0, btn_pin} :    // 0xD0000014：按键
                        32'd0;

    // ---- CPU 例化（观测端口悬空） ----
    cpu_top u_cpu (
        .clk(cpu_clk_out), .rst_n(rst_n),
        .pc_out(), .reg_we(), .reg_wa(), .reg_wd(),
        .mmio_wr(mmio_wr), .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_sel(mmio_sel), .mmio_rdata(mmio_rdata)
    );

    // ---- 引脚输出 ----
    assign led_pin        = led_r;
    assign seg_cs_pin     = segcs_r;
    assign seg_data_0_pin = seg0_r;
    assign seg_data_1_pin = seg1_r;

endmodule
