// ============================================================================
// pipeline_regs.v —— 四级流水寄存器（IF/ID、ID/EX、EX/MEM、MEM/WB）
// ----------------------------------------------------------------------------
// 本文件包含四个独立的寄存器模块，供 cpu_top 例化：
//   if_id_reg  : 保存 PC 与有效位。指令本身由 imem 的同步读输出寄存器提供
//                （见 imem.v 的时序说明），因此这里**不再存 instr**，避免
//                「BRAM 输出寄存器 + IF/ID 寄存器」两级延迟导致 PC/指令错位。
//   id_ex_reg  : 保存译码后的操作数、立即数、ALU 控制与写回目标。
//   ex_mem_reg : 保存 ALU 结果（兼作访存地址）、存储数据与 MEM 级控制。
//   mem_wb_reg : 保存 MEM 级读数据、ALU 结果与 WB 级控制。
//
// 停顿 / 冲刷约定（Step 1 预留，恒 0）：
//   en    = ~stall，为 0 时整级保持
//   flush = 1 时清有效位与控制信号，注入 bubble
// Step 1 中 stall/flush 均接常量 0，行为等价于每拍前进。
// ============================================================================

// ----------------------------------------------------------------------------
// IF/ID：PC + 有效位
// ----------------------------------------------------------------------------
module if_id_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        flush,
    input  wire [31:0] pc_in,
    input  wire        valid_in,
    output reg  [31:0] pc_out,
    output reg         valid_out
);

    always @(posedge clk) begin
        if (!rst_n) begin
            pc_out    <= 32'd0;
            valid_out <= 1'b0;
        end else if (flush) begin
            valid_out <= 1'b0;
        end else if (en) begin
            pc_out    <= pc_in;
            valid_out <= valid_in;
        end
    end

endmodule

// ----------------------------------------------------------------------------
// ID/EX：操作数 + 控制
// ----------------------------------------------------------------------------
module id_ex_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        flush,
    input  wire        valid_in,
    input  wire [31:0] pc_in,
    input  wire [31:0] alu_a_in,
    input  wire [31:0] alu_b_in,
    input  wire [31:0] store_data_in,
    input  wire [4:0]  shamt_in,
    input  wire [5:0]  alu_op_in,
    input  wire [4:0]  dest_in,
    input  wire        reg_we_in,
    input  wire        mem_wen_in,
    input  wire [2:0]  mem_sel_in,
    input  wire [2:0]  wb_sel_in,
    output reg         valid_out,
    output reg  [31:0] pc_out,
    output reg  [31:0] alu_a_out,
    output reg  [31:0] alu_b_out,
    output reg  [31:0] store_data_out,
    output reg  [4:0]  shamt_out,
    output reg  [5:0]  alu_op_out,
    output reg  [4:0]  dest_out,
    output reg         reg_we_out,
    output reg         mem_wen_out,
    output reg  [2:0]  mem_sel_out,
    output reg  [2:0]  wb_sel_out
);

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_out      <= 1'b0;
            pc_out         <= 32'd0;
            alu_a_out      <= 32'd0;
            alu_b_out      <= 32'd0;
            store_data_out <= 32'd0;
            shamt_out      <= 5'd0;
            alu_op_out     <= 6'd0;
            dest_out       <= 5'd0;
            reg_we_out     <= 1'b0;
            mem_wen_out    <= 1'b0;
            mem_sel_out    <= 3'd0;
            wb_sel_out     <= 3'd0;
        end else if (flush) begin
            valid_out      <= 1'b0;
            alu_op_out     <= 6'd0;
            reg_we_out     <= 1'b0;
            mem_wen_out    <= 1'b0;
            mem_sel_out    <= 3'd0;
            wb_sel_out     <= 3'd0;
        end else if (en) begin
            valid_out      <= valid_in;
            pc_out         <= pc_in;
            alu_a_out      <= alu_a_in;
            alu_b_out      <= alu_b_in;
            store_data_out <= store_data_in;
            shamt_out      <= shamt_in;
            alu_op_out     <= alu_op_in;
            dest_out       <= dest_in;
            reg_we_out     <= reg_we_in;
            mem_wen_out    <= mem_wen_in;
            mem_sel_out    <= mem_sel_in;
            wb_sel_out     <= wb_sel_in;
        end
    end

endmodule

// ----------------------------------------------------------------------------
// EX/MEM：ALU 结果（访存地址）+ 存储数据 + MEM 级控制
// ----------------------------------------------------------------------------
module ex_mem_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        flush,
    input  wire        valid_in,
    input  wire [31:0] alu_res_in,
    input  wire [31:0] store_data_in,
    input  wire [31:0] pc_in,
    input  wire [4:0]  dest_in,
    input  wire        reg_we_in,
    input  wire        mem_wen_in,
    input  wire [2:0]  mem_sel_in,
    input  wire [2:0]  wb_sel_in,
    output reg         valid_out,
    output reg  [31:0] alu_res_out,
    output reg  [31:0] store_data_out,
    output reg  [31:0] pc_out,
    output reg  [4:0]  dest_out,
    output reg         reg_we_out,
    output reg         mem_wen_out,
    output reg  [2:0]  mem_sel_out,
    output reg  [2:0]  wb_sel_out
);

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_out      <= 1'b0;
            alu_res_out    <= 32'd0;
            store_data_out <= 32'd0;
            pc_out         <= 32'd0;
            dest_out       <= 5'd0;
            reg_we_out     <= 1'b0;
            mem_wen_out    <= 1'b0;
            mem_sel_out    <= 3'd0;
            wb_sel_out     <= 3'd0;
        end else if (flush) begin
            valid_out      <= 1'b0;
            mem_wen_out    <= 1'b0;
            reg_we_out     <= 1'b0;
            mem_sel_out    <= 3'd0;
            wb_sel_out     <= 3'd0;
        end else if (en) begin
            valid_out      <= valid_in;
            alu_res_out    <= alu_res_in;
            store_data_out <= store_data_in;
            pc_out         <= pc_in;
            dest_out       <= dest_in;
            reg_we_out     <= reg_we_in;
            mem_wen_out    <= mem_wen_in;
            mem_sel_out    <= mem_sel_in;
            wb_sel_out     <= wb_sel_in;
        end
    end

endmodule

// ----------------------------------------------------------------------------
// MEM/WB：访存读数据 + ALU 结果 + WB 级控制
// ----------------------------------------------------------------------------
module mem_wb_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        flush,
    input  wire        valid_in,
    input  wire [31:0] alu_res_in,
    input  wire [31:0] mem_rdata_in,
    input  wire [31:0] pc_in,
    input  wire [4:0]  dest_in,
    input  wire        reg_we_in,
    input  wire [2:0]  wb_sel_in,
    output reg         valid_out,
    output reg  [31:0] alu_res_out,
    output reg  [31:0] mem_rdata_out,
    output reg  [31:0] pc_out,
    output reg  [4:0]  dest_out,
    output reg         reg_we_out,
    output reg  [2:0]  wb_sel_out
);

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_out     <= 1'b0;
            alu_res_out   <= 32'd0;
            mem_rdata_out <= 32'd0;
            pc_out        <= 32'd0;
            dest_out      <= 5'd0;
            reg_we_out    <= 1'b0;
            wb_sel_out    <= 3'd0;
        end else if (flush) begin
            valid_out     <= 1'b0;
            reg_we_out    <= 1'b0;
            wb_sel_out    <= 3'd0;
        end else if (en) begin
            valid_out     <= valid_in;
            alu_res_out   <= alu_res_in;
            mem_rdata_out <= mem_rdata_in;
            pc_out        <= pc_in;
            dest_out      <= dest_in;
            reg_we_out    <= reg_we_in;
            wb_sel_out    <= wb_sel_in;
        end
    end

endmodule
