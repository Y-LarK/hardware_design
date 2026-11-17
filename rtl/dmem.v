// ============================================================================
// 来源：archive/single_cycle/rtl/dmem.v（流水线 Step 1 复用）
// 改动：异步读改为同步读；MMIO 段判断与读写旁路保留归档做法。
// ----------------------------------------------------------------------------
// dmem.v —— 数据存储器（流水线版：同步读，BRAM 推断）+ MMIO 译码
// ----------------------------------------------------------------------------
// 容量：8 KB = 2048 × 32 位（地址用 addr[12:2]，忽略高位）
// 字节序：小端（little-endian，LA32R 手册规定）
// 访问类型 mem_sel（由 control.v 译码）：
//   0=LD.B 1=LD.H 2=LD.W 3=LD.BU 4=LD.HU 5=ST.B 6=ST.H 7=ST.W
//
// 时序对齐（DESIGN.md §3.5，P0 决策）：
//   raddr 是 EX 级 ALU 结果（本条指令的访存地址），在 EX→MEM 边沿被同步读
//   输出寄存器采样；同一沿 EX/MEM 寄存器也捕获该地址。于是 MEM 级期间：
//     mem_word = mem[EX/MEM.addr]
//     addr / mem_sel = 同一条指令的 MEM 级地址与访问类型
//   MEM/WB 在 MEM→WB 边沿捕获 rdata，load 数据因此恰好在 MEM 级末有效。
//   **不要**改用在 MEM 级才给地址的同步读，否则会多错一拍。
//
// MMIO：地址高 4 位 == 0xD（0xD0000000 段）时路由到外设，不访问本 RAM：
//   - 写：不写 RAM，输出 mmio_wr 脉冲 + 地址/数据/类型给外设
//   - 读：rdata 直接取 mmio_rdata（组合旁路），不取 BRAM 输出
// 对齐约定（DESIGN.md §3.7）：不实现非对齐例外，硬件按「取对齐部分」简化。
//
// 写通路（BRAM 推断，DESIGN.md §3.5 要求 2×BRAM36）：
//   字节/半字写不直接对存储器字做位选赋值，而是先译出 4 位字节使能
//   we_bytes[3:0]，再由同一个同步写口按字节分别写入。Vivado 对
//   「单写口 + 每字节独立使能」可推断为 byte-write-enable BRAM；
//   对 `mem[addr][7:0] <= ...` 这种字内位选则可能退化为分布式 RAM。
//   读路径、MMIO 判定与 raddr/addr 的时序分工不受影响。
// ============================================================================
module dmem (
    input  wire        clk,        // 时钟
    input  wire        rst_n,      // 复位（低有效，同步；仅清读输出寄存器）
    input  wire [31:0] raddr,      // EX 级访存地址：同步读地址口
    input  wire [31:0] addr,       // MEM 级访存地址：写 / MMIO / 宽度选择
    input  wire [31:0] wdata,      // 写数据（EX/MEM 捕获的 rd2）
    input  wire        mem_wen,    // 写使能（cpu_top 已与 EX/MEM.valid 相与）
    input  wire [2:0]  mem_sel,    // 访问类型（见上）
    input  wire [31:0] mmio_rdata, // MMIO 读数据（外设返回）
    output wire [31:0] rdata,      // MEM 级读数据（对齐 + 符号/零扩展）
    // MMIO 写接口（发给上板顶层的外设寄存器）
    output wire        mmio_wr,
    output wire [31:0] mmio_addr,
    output wire [31:0] mmio_wdata,
    output wire [2:0]  mmio_sel_out
);

    reg [31:0] mem [0:2047];       // 2048 × 32 同步读 RAM
    reg [31:0] mem_word;           // 同步读输出（与 MEM 级地址同拍对齐）
    integer i;

    // 数据区清零（BRAM 初始化）
    initial for (i = 0; i < 2048; i = i + 1) mem[i] = 32'd0;

    // ---- MMIO 段判断：沿用归档 dmem.v 的做法（高 4 位 == 0xD） ----
    // rd_mmio 对应 EX 级地址，用于决定是否让同步读进入 BRAM；
    // wr_mmio 对应 MEM 级地址，用于写屏蔽与读数据旁路。
    wire rd_mmio = (raddr[31:28] == 4'hD);
    wire wr_mmio = (addr[31:28]  == 4'hD);

    // ---- 同步读：EX→MEM 边沿采样，MEM 级期间输出有效 ----
    always @(posedge clk) begin
        if (!rst_n)
            mem_word <= 32'd0;
        else if (!rd_mmio)
            mem_word <= mem[raddr[12:2]];
        else
            mem_word <= 32'd0;     // MMIO 段不访问 BRAM
    end

    // ---- 组合对齐 / 扩展：使用 MEM 级 addr 与 mem_sel，与 mem_word 同拍 ----
    reg [31:0] rd_tmp;
    always @(*) begin
        case (mem_sel)
            3'd0: begin // LD.B：符号扩展
                case (addr[1:0])
                    2'd0:  rd_tmp = {{24{mem_word[7]}},   mem_word[7:0]};
                    2'd1:  rd_tmp = {{24{mem_word[15]}},  mem_word[15:8]};
                    2'd2:  rd_tmp = {{24{mem_word[23]}},  mem_word[23:16]};
                    default: rd_tmp = {{24{mem_word[31]}}, mem_word[31:24]};
                endcase
            end
            3'd1: begin // LD.H：符号扩展（半字必须按 2 对齐）
                case (addr[1])
                    1'd0: rd_tmp = {{16{mem_word[15]}}, mem_word[15:0]};
                    default: rd_tmp = {{16{mem_word[31]}}, mem_word[31:16]};
                endcase
            end
            3'd2: rd_tmp = mem_word;                           // LD.W
            3'd3: begin // LD.BU：零扩展
                case (addr[1:0])
                    2'd0:  rd_tmp = {24'd0, mem_word[7:0]};
                    2'd1:  rd_tmp = {24'd0, mem_word[15:8]};
                    2'd2:  rd_tmp = {24'd0, mem_word[23:16]};
                    default: rd_tmp = {24'd0, mem_word[31:24]};
                endcase
            end
            3'd4: begin // LD.HU：零扩展
                case (addr[1])
                    1'd0: rd_tmp = {16'd0, mem_word[15:0]};
                    default: rd_tmp = {16'd0, mem_word[31:16]};
                endcase
            end
            default: rd_tmp = 32'd0;   // ST 类不读
        endcase
    end

    // MMIO 读走组合旁路；普通访存取同步读输出
    assign rdata = wr_mmio ? mmio_rdata : rd_tmp;

    // ---- 同步写：显式字节使能（小端），MMIO 段不写 RAM ----
    // BRAM 推断要求写口是「每个字节独立的写使能」，而不是对存储器字做位选赋值。
    // 这里先把访存类型与地址偏移译成 4 位字节使能 we_bytes，再用同一写口按字节
    // 分别写入：Vivado 可据此推断 2×BRAM36 的 byte-write-enable 模式。
    // 语义与归档版逐字节等价：ST.B 只写 1 个字节、ST.H 写对齐的低/高半字、
    // ST.W 写整字；wdata 的字节位置固定，与地址偏移无关（小端）。
    reg  [3:0] we_bytes;
    always @(*) begin
        we_bytes = 4'b0000;
        if (mem_wen && !wr_mmio) begin
            case (mem_sel)
                3'd5: begin                      // ST.B：按 addr[1:0] 选中一个字节
                    case (addr[1:0])
                        2'd0:    we_bytes = 4'b0001;
                        2'd1:    we_bytes = 4'b0010;
                        2'd2:    we_bytes = 4'b0100;
                        default: we_bytes = 4'b1000;
                    endcase
                end
                3'd6: begin                      // ST.H：按 addr[1] 选低/高半字
                    case (addr[1])
                        1'd0:    we_bytes = 4'b0011;
                        default: we_bytes = 4'b1100;
                    endcase
                end
                3'd7:    we_bytes = 4'b1111;      // ST.W：整字
                default: we_bytes = 4'b0000;
            endcase
        end
    end

    // BRAM 写口每个字节通道的数据取自同一个 32 位 din 的对应字节，
    // 而 ST.B / ST.H 的数据始终来自 wdata 的低字节 / 低半字，因此先把 wdata
    // 复制到所有可能的字节通道：
    //   ST.B：{4{wdata[7:0]}}  —— 由 we_bytes 选中其中一个字节
    //   ST.H：{2{wdata[15:0]}} —— 由 we_bytes 选中低/高半字
    //   ST.W：wdata
    reg  [31:0] wdata_be;
    always @(*) begin
        case (mem_sel)
            3'd5:    wdata_be = {4{wdata[7:0]}};
            3'd6:    wdata_be = {2{wdata[15:0]}};
            3'd7:    wdata_be = wdata;
            default: wdata_be = 32'd0;
        endcase
    end

    // 单一写口 + 逐字节使能（BRAM 可推断写法）
    always @(posedge clk) begin
        if (we_bytes[0]) mem[addr[12:2]][7:0]   <= wdata_be[7:0];
        if (we_bytes[1]) mem[addr[12:2]][15:8]  <= wdata_be[15:8];
        if (we_bytes[2]) mem[addr[12:2]][23:16] <= wdata_be[23:16];
        if (we_bytes[3]) mem[addr[12:2]][31:24] <= wdata_be[31:24];
    end

    // ---- MMIO 写接口 ----
    assign mmio_wr      = mem_wen && wr_mmio;
    assign mmio_addr    = addr;
    assign mmio_wdata   = wdata;
    assign mmio_sel_out = mem_sel;

endmodule
