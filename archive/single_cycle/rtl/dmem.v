// ============================================================================
// dmem.v —— 数据存储器（单周期版：分布式 RAM，异步读）+ MMIO 译码
// ----------------------------------------------------------------------------
// 容量：8 KB = 2048 × 32 位（地址用 alu_res[12:2]，忽略高位）
// 字节序：小端（little-endian，LA32R 手册规定）
// 访问类型 mem_sel（由 control.v 译码）：
//   0=LD.B 1=LD.H 2=LD.W 3=LD.BU 4=LD.HU 5=ST.B 6=ST.H 7=ST.W
// 读：异步（组合逻辑），按宽度取数并做符号/零扩展
// 写：时钟上升沿，按字节/半字掩码写入（小端字节定位）
// MMIO：地址高 4 位 == 0xD（0xD0000000 段）时路由到外设，不访问本 RAM：
//   - 读：rdata 直接取 mmio_rdata（由上板顶层译码外设寄存器）
//   - 写：不写 RAM，输出 mmio_wr 脉冲 + 地址/数据/类型给外设
// 对齐约定（DESIGN.md §3.7）：本设计不实现非对齐例外，测试程序保证访存
//   自然对齐；硬件对非对齐地址按「取对齐部分」简化处理。
// ============================================================================
module dmem (
    input  wire        clk,        // 时钟
    input  wire [31:0] addr,       // 访存地址（ALU 结果）
    input  wire [31:0] wdata,      // 写数据（寄存器堆 rd2）
    input  wire        mem_wen,    // 写使能
    input  wire [2:0]  mem_sel,    // 访问类型（见上）
    input  wire        mmio_sel,   // 地址落在 MMIO 段（0xD0000000）
    input  wire [31:0] mmio_rdata, // MMIO 读数据（外设返回）
    output wire [31:0] rdata,      // 读数据（对齐 + 符号/零扩展）
    // MMIO 写接口（发给上板顶层的外设寄存器）
    output wire        mmio_wr,
    output wire [31:0] mmio_addr,
    output wire [31:0] mmio_wdata,
    output wire [2:0]  mmio_sel_out
);

    reg [31:0] mem [0:2047];       // 2048 × 32 分布式 RAM
    integer i;
    initial for (i = 0; i < 2048; i = i + 1) mem[i] = 32'd0;   // 数据区清零

    // ---- 异步读：按类型取数并扩展 ----
    reg [31:0] rd_tmp;
    always @(*) begin
        case (mem_sel)
            3'd0: begin // LD.B：符号扩展
                case (addr[1:0])
                    2'd0:  rd_tmp = {{24{mem[addr[12:2]][7]}},   mem[addr[12:2]][7:0]};
                    2'd1:  rd_tmp = {{24{mem[addr[12:2]][15]}},  mem[addr[12:2]][15:8]};
                    2'd2:  rd_tmp = {{24{mem[addr[12:2]][23]}},  mem[addr[12:2]][23:16]};
                    default: rd_tmp = {{24{mem[addr[12:2]][31]}}, mem[addr[12:2]][31:24]};
                endcase
            end
            3'd1: begin // LD.H：符号扩展（半字必须按 2 对齐）
                case (addr[1])
                    1'd0: rd_tmp = {{16{mem[addr[12:2]][15]}}, mem[addr[12:2]][15:0]};
                    default: rd_tmp = {{16{mem[addr[12:2]][31]}}, mem[addr[12:2]][31:16]};
                endcase
            end
            3'd2: rd_tmp = mem[addr[12:2]];                    // LD.W
            3'd3: begin // LD.BU：零扩展
                case (addr[1:0])
                    2'd0:  rd_tmp = {24'd0, mem[addr[12:2]][7:0]};
                    2'd1:  rd_tmp = {24'd0, mem[addr[12:2]][15:8]};
                    2'd2:  rd_tmp = {24'd0, mem[addr[12:2]][23:16]};
                    default: rd_tmp = {24'd0, mem[addr[12:2]][31:24]};
                endcase
            end
            3'd4: begin // LD.HU：零扩展
                case (addr[1])
                    1'd0: rd_tmp = {16'd0, mem[addr[12:2]][15:0]};
                    default: rd_tmp = {16'd0, mem[addr[12:2]][31:16]};
                endcase
            end
            default: rd_tmp = 32'd0;   // ST 类不读
        endcase
    end
    assign rdata = mmio_sel ? mmio_rdata : rd_tmp;

    // ---- 同步写：字节 / 半字掩码（小端） ----
    always @(posedge clk) begin
        if (mem_wen && !mmio_sel) begin
            case (mem_sel)
                3'd5: begin // ST.B
                    case (addr[1:0])
                        2'd0:  mem[addr[12:2]][7:0]   <= wdata[7:0];
                        2'd1:  mem[addr[12:2]][15:8]  <= wdata[7:0];
                        2'd2:  mem[addr[12:2]][23:16] <= wdata[7:0];
                        default: mem[addr[12:2]][31:24] <= wdata[7:0];
                    endcase
                end
                3'd6: begin // ST.H
                    case (addr[1])
                        1'd0: mem[addr[12:2]][15:0]  <= wdata[15:0];
                        default: mem[addr[12:2]][31:16] <= wdata[15:0];
                    endcase
                end
                3'd7: mem[addr[12:2]] <= wdata;           // ST.W
                default: ;
            endcase
        end
    end

    // ---- MMIO 写接口 ----
    assign mmio_wr    = mem_wen && mmio_sel;
    assign mmio_addr  = addr;
    assign mmio_wdata = wdata;
    assign mmio_sel_out = mem_sel;

endmodule
