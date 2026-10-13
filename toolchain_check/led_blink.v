// ============================================================
// EGO1 工具链验证工程：16 个 LED 二进制计数
// 时钟: 100MHz (P17)   复位: sys_rst_n 低有效 (P15)
// 用途: 验证 Vivado 综合 -> 实现 -> 生成比特流 全流程
// ============================================================
`timescale 1ns / 1ps

module led_blink (
    input  wire        sys_clk_in,   // 100MHz 系统时钟
    input  wire        sys_rst_n,    // 低有效复位
    output wire [15:0] led_pin       // 16 个 LED (LD0~LD15)
);

    // 100MHz 分频出 0.5s 使能：计数到 50_000_000-1
    localparam [25:0] DIV_MAX = 26'd49_999_999;

    reg [25:0] div_cnt;
    reg [15:0] led_reg;

    always @(posedge sys_clk_in or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            div_cnt <= 26'd0;
            led_reg <= 16'd0;
        end else if (div_cnt == DIV_MAX) begin
            div_cnt <= 26'd0;
            led_reg <= led_reg + 16'd1;   // 每 0.5s 加一，肉眼可见二进制计数
        end else begin
            div_cnt <= div_cnt + 26'd1;
        end
    end

    assign led_pin = led_reg;

endmodule
