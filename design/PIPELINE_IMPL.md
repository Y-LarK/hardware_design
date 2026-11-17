# 流水线 Step 1：骨架直通实现与验收

> 对应分支：`feat/pipeline-core`，基线提交 `4178f16`。
> 本文记录 Step 1 的实现口径、逐拍时序、模块端口与验收结果。
> 设计总纲仍以 [DESIGN.md](DESIGN.md) 为准；本文只补充落地细节。

## 1. 范围

Step 1 只实现「五级流水骨架直通」：

- IF → ID → EX → MEM → WB 五级寄存边界完整；
- IMEM / DMEM 使用 BRAM 同步读，输出寄存器纳入流水时序；
- 寄存器堆支持 2 读 1 写与同拍写穿透；
- MMIO 地址段组合旁路，写外设不写 DMEM；
- `stall` / `flush` 端口预留，Step 1 恒 0；
- PC 每拍 `+4`。

**明确不做**：转发、冒险检测、load-use 停顿、分支/跳转正确执行、MDU 握手、
分支预测、性能计数器、`cpu_pipeline_board.v`。分支/跳转/MUL/DIV 可以译码，
但 Step 1 不保证结果正确，测试程序也不包含它们。

## 2. 五级划分

| 级 | 主要模块 | 寄存器边界 | 说明 |
| --- | --- | --- | --- |
| IF | `pc.v`、`imem.v` | `IF/ID` | PC 送 IMEM 地址；IMEM 同步读输出即 IF/ID 指令部分 |
| ID | `control.v`、`regfile.v`、`imm_ext.v` | `ID/EX` | 译码、读寄存器堆、扩展立即数、算好 ALU B 与 shamt |
| EX | `alu.v` | `EX/MEM` | ALU 运算；访存地址在此产生 |
| MEM | `dmem.v` | `MEM/WB` | DMEM 同步读在 MEM 级有效；写 / MMIO 在 MEM 级末生效 |
| WB | `regfile.v` 写口 | — | 按 `wb_sel` 选 ALU / DMEM / PC+4 写回 |

## 3. 逐拍时序图

### 3.1 取指与 IF/ID 对齐（P0 决策）

约定：`P0` 为复位释放后的第一个时钟上升沿；`Ik` 表示第 k 条指令，
`PCk = 0x1C000000 + 4*k`。

```
周期(沿后)   PC 寄存器   IMEM 输出   IF/ID.pc / 指令      ID/EX   EX/MEM  MEM/WB  WB 写回
------------------------------------------------------------------------------------------
复位期间     1C000000    0           -                     -       -       -       -
P0           1C000004    I0          1C000000 / I0         -       -       -       -
P1           1C000008    I1          1C000004 / I1         I0      -       -       -
P2           1C00000C    I2          1C000008 / I2         I1      I0      -       -
P3           1C000010    I3          1C00000C / I3         I2      I1      I0      -
P4           1C000014    I4          1C000010 / I4         I3      I2      I1      I0
P5           1C000018    I5          1C000014 / I5         I4      I3      I2      I1
```

关键点：

- `pc` 与 `imem` 输出寄存器在**同一个沿**更新；
- `IF/ID` 只再寄存一拍 `pc` 与 `valid`，**不寄存 `instr`**；
- 因此 `P0` 之后，`IF/ID.pc = 1C000000` 与 `IMEM 输出 = I0` 严格配对；
- 若在 `IF/ID` 里再加一级 `instr` 寄存器，就会变成
  「BRAM 输出寄存器 + IF/ID 寄存器」两级延迟，`PC` 与指令错位一拍，
  这是 DESIGN.md §3.5 明确禁止的做法。

### 3.2 指令在各级的边界（以 I0 为例）

```
          P0        P1        P2        P3        P4        P5
IF        I0
ID                  I0
EX                            I0
MEM                                     I0
WB                                                I0(写回)
```

### 3.3 DMEM 同步读对齐

DMEM 的同步读地址取 **EX 级 ALU 结果**，而不是 EX/MEM 里的地址：

```
EX 级（I0）            : alu_res = addr_I0
沿 EX→MEM              : mem_word <= mem[addr_I0]
                         EX/MEM.addr <= addr_I0
MEM 级（I0）           : mem_word = mem[addr_I0]
                         addr = addr_I0, mem_sel = sel_I0
                         组合对齐 / 符号扩展 -> rdata
沿 MEM→WB              : MEM/WB.mem_rdata <= rdata
```

这样 `mem_word` 与 MEM 级的 `addr` / `mem_sel` 同拍，load 数据在 MEM 级末
有效，由 MEM/WB 捕获。若改成「MEM 级才把地址送给同步读」，数据会晚一拍，
MEM/WB 将捕获到上一条指令的数据。

### 3.4 MMIO 旁路

- 段判断沿用归档 `dmem.v`：`addr[31:28] == 4'hD`；
- 写：`mmio_wr = mem_wen && (addr[31:28] == 4'hD)`，在 MEM 级整拍有效，
  testbench 在 `posedge` 采样；
- 读：`rdata = (addr[31:28] == 4'hD) ? mmio_rdata : rd_tmp`，组合旁路；
- 同步读在 EX→MEM 沿若检测到 EX 级地址落在 MMIO 段，则不读 BRAM。

## 4. 模块端口冻结表

> 「冻结」指 Step 2 增加转发 / 冒险逻辑时应保持这些端口语义不变，
> 只允许新增端口。位宽均为十进制标注。

### 4.1 `cpu_top`

| 端口 | 方向 | 位宽 | 说明 |
| --- | --- | --- | --- |
| `clk` | in | 1 | 时钟 |
| `rst_n` | in | 1 | 复位，低有效，同步 |
| `pc_out` | out | 32 | 当前 PC（观测） |
| `reg_we` | out | 1 | 写回使能（观测） |
| `reg_wa` | out | 5 | 写回地址（观测） |
| `reg_wd` | out | 32 | 写回数据（观测） |
| `mmio_wr` | out | 1 | MMIO 写脉冲 |
| `mmio_addr` | out | 32 | MMIO 地址 |
| `mmio_wdata` | out | 32 | MMIO 写数据 |
| `mmio_sel` | out | 3 | 访存类型 |
| `mmio_rdata` | in | 32 | MMIO 读数据 |

内部 `stall` / `flush` 为常量 0；Step 2 接入冒险单元时改为真实信号。

### 4.2 `pc`

| 端口 | 方向 | 位宽 | 说明 |
| --- | --- | --- | --- |
| `clk` | in | 1 | 时钟 |
| `rst_n` | in | 1 | 复位，低有效，同步 |
| `en` | in | 1 | 使能，0 时保持 |
| `next_pc` | in | 32 | 下一 PC |
| `pc` | out | 32 | 当前 PC，复位值 `0x1C000000` |

### 4.3 `imem`

| 端口 | 方向 | 位宽 | 说明 |
| --- | --- | --- | --- |
| `clk` | in | 1 | 时钟 |
| `rst_n` | in | 1 | 复位，低有效，同步 |
| `addr` | in | 10 | 取指地址 `pc[11:2]` |
| `instr` | out | 32 | 同步读指令，下一拍有效 |

`IMEM_FILE` 宏由 `scripts/sim.sh` / `build.tcl` 传绝对路径。

### 4.4 `dmem`

| 端口 | 方向 | 位宽 | 说明 |
| --- | --- | --- | --- |
| `clk` | in | 1 | 时钟 |
| `rst_n` | in | 1 | 复位，低有效，同步（只清读输出寄存器） |
| `raddr` | in | 32 | EX 级访存地址（同步读地址口） |
| `addr` | in | 32 | MEM 级访存地址（写 / MMIO / 宽度选择） |
| `wdata` | in | 32 | 写数据 |
| `mem_wen` | in | 1 | 写使能（已与 `EX/MEM.valid` 相与） |
| `mem_sel` | in | 3 | 访存类型：0=LD.B 1=LD.H 2=LD.W 3=LD.BU 4=LD.HU 5=ST.B 6=ST.H 7=ST.W |
| `mmio_rdata` | in | 32 | MMIO 读数据 |
| `rdata` | out | 32 | MEM 级读数据（对齐 + 符号/零扩展） |
| `mmio_wr` | out | 1 | MMIO 写脉冲 |
| `mmio_addr` | out | 32 | MMIO 地址 |
| `mmio_wdata` | out | 32 | MMIO 写数据 |
| `mmio_sel_out` | out | 3 | MMIO 访存类型 |

### 4.5 `regfile`

| 端口 | 方向 | 位宽 | 说明 |
| --- | --- | --- | --- |
| `clk` | in | 1 | 时钟 |
| `we` | in | 1 | 写使能 |
| `ra1` | in | 5 | 读地址 1 |
| `ra2` | in | 5 | 读地址 2 |
| `wa` | in | 5 | 写地址 |
| `wd` | in | 32 | 写数据 |
| `rd1` | out | 32 | 读数据 1 |
| `rd2` | out | 32 | 读数据 2 |

写穿透：`we && wa != 0 && wa == raN` 时 `rdN = wd`。

### 4.6 `imm_ext` / `alu` / `control`

三者直接复用归档版本，端口未改动：

| 模块 | 端口（方向/位宽） |
| --- | --- |
| `imm_ext` | `instr`(in/32)、`imm_sel`(in/3)、`imm_out`(out/32) |
| `alu` | `a`(in/32)、`b`(in/32)、`pc`(in/32)、`shamt`(in/5)、`alu_op`(in/6)、`result`(out/32) |
| `control` | `instr`(in/32)；`ra1`(out/5)、`ra2`(out/5)、`reg_we`(out/1)、`alu_src`(out/1)、`imm_sel`(out/3)、`alu_op`(out/6)、`mem_wen`(out/1)、`mem_sel`(out/3)、`wb_sel`(out/3)、`mul_valid`(out/1)、`div_valid`(out/1)、`mul_op`(out/2)、`div_op`(out/2)、`branch_op`(out/3)、`jump_op`(out/2)、`shift_imm`(out/1) |

`control` 的 `mul_valid` / `div_valid` / `mul_op` / `div_op` / `branch_op`
在 Step 1 已连接但未使用；Step 2 接 MDU / 分支单元时保持语义不变。

### 4.7 流水寄存器（`pipeline_regs.v`）

| 模块 | 端口 |
| --- | --- |
| `if_id_reg` | `clk`、`rst_n`、`en`、`flush`、`pc_in`(32)、`valid_in`、`pc_out`(32)、`valid_out` |
| `id_ex_reg` | `clk`、`rst_n`、`en`、`flush`、`valid_in`、`pc_in`(32)、`alu_a_in`(32)、`alu_b_in`(32)、`store_data_in`(32)、`shamt_in`(5)、`alu_op_in`(6)、`dest_in`(5)、`reg_we_in`、`mem_wen_in`、`mem_sel_in`(3)、`wb_sel_in`(3)；对应 `*_out` |
| `ex_mem_reg` | `clk`、`rst_n`、`en`、`flush`、`valid_in`、`alu_res_in`(32)、`store_data_in`(32)、`pc_in`(32)、`dest_in`(5)、`reg_we_in`、`mem_wen_in`、`mem_sel_in`(3)、`wb_sel_in`(3)；对应 `*_out` |
| `mem_wb_reg` | `clk`、`rst_n`、`en`、`flush`、`valid_in`、`alu_res_in`(32)、`mem_rdata_in`(32)、`pc_in`(32)、`dest_in`(5)、`reg_we_in`、`wb_sel_in`(3)；对应 `*_out` |

`en = ~stall`，`flush` 清有效位与控制信号。Step 1 两者均为 0。

## 5. Step 1 验收记录

### 5.1 环境

| 项 | 版本 / 路径 |
| --- | --- |
| Vivado Simulator | v2023.2（`~/Software/Xilinx/Vivado/2023.2`） |
| GNU LoongArch binutils | 2.46.1-1.fc44 |
| 工作目录 | `/home/ylk/orca/workspaces/hardware_design/pipeline-core` |

未运行 Vivado 综合 / 实现 / 烧录，本步只做行为仿真。

### 5.2 命令与结果

```bash
make -C tests/asm test_pipe_basic
./scripts/sim.sh pipeline tests/hex/test_pipe_basic.hex
```

`make` 输出：

```
生成 ../hex/test_pipe_basic.hex ：312 条指令
```

`sim.sh` 输出原文：

```
== RESULT: PASS —— 流水线 MMIO 序列与 DMEM 语义均正确 ==
```

退出码：`0`。

### 5.3 MMIO 写序列（xsim.log 原文）

测试程序把**每一条计算指令**的结果依次写到 LED，再以 4 笔 PASS 序列收尾，
共 30 笔。testbench 按顺序逐笔比对全部 30 笔，任一值不符即 FAIL：

```
[315000] MMIO_WR[0]  addr=d0000000 data=0000000a   addi.w  $r4  = 10
[325000] MMIO_WR[1]  addr=d0000000 data=00000003   addi.w  $r5  = 3
[335000] MMIO_WR[2]  addr=d0000000 data=ffffffff   addi.w  $r6  = -1
[345000] MMIO_WR[3]  addr=d0000000 data=12345000   lu12i.w $r7
[355000] MMIO_WR[4]  addr=d0000000 data=00000f0f   ori     $r8
[365000] MMIO_WR[5]  addr=d0000000 data=000000ff   ori     $r9
[375000] MMIO_WR[6]  addr=d0000000 data=d0000000   lu12i.w $r10
[385000] MMIO_WR[7]  addr=d0000000 data=0000000d   add.w
[395000] MMIO_WR[8]  addr=d0000000 data=fffffff9   sub.w
[405000] MMIO_WR[9]  addr=d0000000 data=00000003   addi.w
[415000] MMIO_WR[10] addr=d0000000 data=0000000f   and
[425000] MMIO_WR[11] addr=d0000000 data=00000fff   or
[435000] MMIO_WR[12] addr=d0000000 data=fffff000   nor
[445000] MMIO_WR[13] addr=d0000000 data=00000ff0   xor
[455000] MMIO_WR[14] addr=d0000000 data=00000050   sll.w
[465000] MMIO_WR[15] addr=d0000000 data=1fffffff   srl.w
[475000] MMIO_WR[16] addr=d0000000 data=ffffffff   sra.w
[485000] MMIO_WR[17] addr=d0000000 data=00000001   slt
[495000] MMIO_WR[18] addr=d0000000 data=00000000   sltu
[505000] MMIO_WR[19] addr=d0000000 data=0000000f   andi
[515000] MMIO_WR[20] addr=d0000000 data=000000f0   xori
[525000] MMIO_WR[21] addr=d0000000 data=000000a0   slli.w
[535000] MMIO_WR[22] addr=d0000000 data=0000000f   srli.w
[545000] MMIO_WR[23] addr=d0000000 data=0000007f   ori
[555000] MMIO_WR[24] addr=d0000000 data=ffffffff   srai.w
[565000] MMIO_WR[25] addr=d0000000 data=1c001064   pcaddu12i
[575000] MMIO_WR[26] addr=d0000000 data=ffffffff   LED       <- 0xFFFFFFFF
[585000] MMIO_WR[27] addr=d000000c data=ffffffff   seg_cs    <- 0xFFFFFFFF
[595000] MMIO_WR[28] addr=d0000004 data=0000007f   seg_data0 <- 0x7F
[605000] MMIO_WR[29] addr=d0000008 data=0000007f   seg_data1 <- 0x7F
== RESULT: PASS —— 流水线 MMIO 序列与 DMEM 语义均正确 ==
```

`pcaddu12i $r28, 1` 位于索引 25（地址 `0x1C000064`），因此
`rd = 0x1C000064 + 0x1000 = 0x1C001064`；该地址已用 `objdump` 反汇编核对。

由于 18 条必须覆盖的计算指令（`add.w` / `sub.w` / `addi.w` / `lu12i.w` /
`and` / `or` / `nor` / `xor` / `andi` / `ori` / `xori` / `sll.w` / `srl.w` /
`sra.w` / `slli.w` / `srli.w` / `srai.w` / `slt` / `sltu`）的结果全部进入
写序列，新增了变异验证：把 `alu.v` 的 `6'd2`（AND）改成 OR 后，写序列
第 10、19 笔不匹配、仿真 FAIL；恢复后 PASS。

### 5.3.1 DMEM 单元测试

Step 1 的 CPU 测试程序只写 MMIO、不访问 DMEM，因此 `sim/tb_pipeline.v`
额外例化一个独立的 `dmem` 实例，直接验证：

- `ST.W` / `ST.H` / `ST.B` 的字节使能与小端字节布局（4 个字节通道全覆盖）；
- `LD.W` / `LD.H` / `LD.HU` / `LD.B` / `LD.BU` 的对齐与符号/零扩展；
- MMIO 地址写产生 `mmio_wr` 脉冲且不改动 RAM。

变异验证：把 `dmem.v` 中 `ST.B` 的 `addr[1:0]==2'd2` 字节通道改错后，
该单元测试输出 3 条 `DMEM FAIL` 并整体 FAIL；恢复后 PASS。

### 5.4 测试程序时序约束

`tests/asm/test_pipe_basic.s` 的生产/消费距离均 ≥ 5 条指令：

- 启动常量 `$r4..$r10` 在计算块之前写入；
- 计算块只读这些常量，结果写入互不相同的寄存器；
- 结尾 26 条 `st.w` 才读取结果寄存器，最近的生产/消费距离为 19 条；
- 无分支、无跳转、无乘除、无 DMEM 读写（仅 MMIO 写）；
- 末尾 256 条 `addi.w $zero,$zero,0` 填充，避免 testbench 结束前取到未初始化 IMEM。


## 6. 与计划的偏离

- 无功能偏离。`imem` / `dmem` 按 Step 1 决策改为同步读；`regfile` 增加写穿透；
  其余复用模块（`alu` / `control` / `imm_ext` / `pc`）逻辑未改动，仅在文件头注明来源。
- `tests/asm/Makefile` 只新增独立目标 `test_pipe_basic`，默认 `all` 与
  `tests/hex/test_all.hex` 未改动；`scripts/build.tcl` / `create_project.tcl`
  的 `$hex` 未改动。

## 7. 遗留风险与 Step 2 待办

1. **无转发**：任何相邻 RAW 都会读旧值。Step 1 测试已刻意拉开距离，不能用于
   验证冒险逻辑。
2. **无 load-use 停顿**：DMEM 同步读的时序已按「MEM 级末有效」留对，但
   Step 2 必须补 `EX/MEM -> EX`、`MEM/WB -> EX` 转发与 load-use 停顿。
3. **分支/跳转未实现**：PC 恒 `+4`，`branch_op` / `jump_op` 只译码不执行。
4. **MDU 未实现**：`wb_sel=2/3` 暂按 ALU 结果处理；测试程序不含乘除。
5. **MMIO 读未覆盖**：testbench 将 `mmio_rdata` 接 0，且测试程序不做 MMIO load。
6. **未综合**：同步读与 byte-write-enable 写口是否能按预期推断为 BRAM
   （IMEM 1×BRAM36、DMEM 2×BRAM36）、时序是否收敛，需 Step 2 后跑
   Vivado 综合 / 实现确认；行为仿真无法证明推断结果。
7. **未做 `cpu_pipeline_board.v`**：上板顶层留到后续步骤，当前 `build.tcl`
   的 `pipeline` 顶层 `cpu_pipeline_board` 仍不存在，不能用于综合。
