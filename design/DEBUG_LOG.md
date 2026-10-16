# 调试记录 · 上板全黑问题

> 记录日期：2026-10-16
> 现象：同一份单周期 CPU RTL，**Windows 工程上板 LED 全亮，Linux 工程上板 LED 全黑**
> 结论：**两个独立缺陷叠加**，逐层剥离后修复，最终仿真与上板均通过

---

## 0. 现象与初始误判

| 环境 | 上板现象 |
|------|----------|
| 队友 Windows + Vivado 2019.1 | LED 全亮（正常） |
| 本机 Linux + Vivado 2023.2 | LED 全黑 |

第一反应是「Linux 版工程哪里不一样」，于是先查工程配置差异。**这个方向对，但第一个抓到的
根因是错的**——见案例 1 的纠正说明。

---

## 1. 案例 1：`$readmemh` 读不到文件 → IMEM 全空

### 症状线索

综合日志出现：

```
CRITICAL WARNING: [Synth 8-4445] could not open $readmem data file 'test_all.hex';
please make sure the file is added to project and has read permission, ignoring
WARNING: [Synth 8-3848] Net mem in module/entity imem does not have driver.   ← 共 100 条
```

### 根因

`imem.v` 的 `$readmemh(IMEM_FILE, mem)` 以**综合运行目录**为基准解析路径，而：

- `test_all.hex` 在工程里只挂在 **`sim_1` 文件集**下 → **不参与综合**，运行目录里没有它
- Windows 工程恰好把 hex 放对了位置 → 能读到 → 全亮

**关键陷阱**：`$readmemh` 失败只是 `CRITICAL WARNING`，**bit 流照常生成**。烧进去的是一片
全 0 的 IMEM，CPU 取到的指令全是 0，于是 LED 全黑——**不报错、难察觉**。

### 修复

不改文件位置，改用**综合宏传绝对路径**（与工作目录无关）：

```tcl
set_property verilog_define [list IMEM_FILE=\"/abs/path/tests/hex/test_all.hex\"] [current_fileset]
reset_run synth_1
```

验证判据：日志须出现 `INFO: [Synth 8-3876] $readmem data file '...' is read successfully`，
且 `does not have driver` 警告从 100 条降为 **0 条**。

### ⚠️ 这还不是全部——**当时的自我纠错**

修完此项后重新烧板，**仍然是全黑**。说明 `$readmemh` 失败虽是真问题，但**不是全黑的原因**。

回头看，真正的教训是：我在只掌握「日志有 CRITICAL WARNING」这一条证据时，就把它断定为根因
并向用户下了结论。**日志报错 ≠ 就是这个症状的原因**。继续挖才找到案例 2。

详细描述见 DESIGN.md §3.5.1。

---

## 2. 案例 2：分支偏移解码与 LA32R 标准不符（真凶）

### 症状线索

`$readmemh` 修好后，硬件行为**仍然不对**。转而怀疑「程序本身是否真的在跑」，
于是用 iverilog 做**仿真**（比烧板快，且可观测）。

### 根因：I26 编码理解错误

`cpu_top.v` 原来这样解码 `B`/`BL` 的 26 位偏移：

```verilog
wire [25:0] offs26 = instr[25:0];                        // ✗ 错误
wire [31:0] jump_target_i26 = pc + {{4{offs26[25]}}, offs26, 2'b00};
```

**LA32R 标准的 I26 是分两段存放的**：

```verilog
wire [25:0] offs26 = {instr[9:0], instr[25:10]};         // ✓ 正确
```

### 实验证据（binutils 2.46.1 实测）

```asm
b  +0x10          → 机器码 50001000
  · 标准解码 {instr[9:0], instr[25:10]}  = 4 字 (16 字节)   ✓
  · 原 RTL 连续解码 instr[25:0]          = 4096 字 (16 KB)  ✗ 跳飞
```

**根因的根因**：`DESIGN.md` §2.4 编码表当时把 I26 写成 `` `offs26[25:0]` 连续 ``，
RTL 照着文档写，于是**文档错 → 代码错**，一致地错，谁也没发现。

### 为什么原 hex 能跑通

原 `test_all.hex` 里那 10 条分支（9 条 `b` + 1 条 `bl`）是**手工按错误解码构造偏移**的，
例如 `0x320: 50000002` 的 `[25:0]=2`，按连续解码恰好是 +8 字节，**歪打正着**。

这意味着一件事：**改用标准汇编器（binutils）生成程序后，原 hex 必然失效**——
因为 binutils 按标准编码，而 RTL 按非标准解码。二者必须统一。

### 修复

```verilog
- wire [25:0] offs26 = instr[25:0];
+ wire [25:0] offs26 = {instr[9:0], instr[25:10]};
```

顺带核对了其他分支类指令，**均为正确**，未受影响：

- `BEQ`/`BNE`/`BLT` 等 2RI16：`offs16 = instr[25:10]` ✓ 与标准一致
- `JIRL`：`rd1 + sext(instr[25:10])<<2` ✓ 一致

---

## 3. 配套工作：还原汇编源并验证

修完解码后需要一份**与标准编码匹配**的测试程序。原仓库只有编译后的 hex，
没有汇编源（`.s`），这在答辩时是硬伤（老师问「测试程序是你写的吗、改一条看看」会拿不出东西）。

### 3.1 从 hex 反汇编还原

```bash
python3 -c "..."                                        # hex -> 小端二进制 prog.bin
loongarch64-linux-gnu-objdump -D -b binary -m loongarch64 -EL prog.bin
```

得到 252 条指令的完整反汇编，识别出程序结构：**8 个测试组、47 种助记符**。

> ⚠️ `objdump` 的架构名要用 `-m loongarch64`，**不是** `loongarch:la32`（后者报
> `can't use supplied machine`）。

### 3.2 产出汇编源

`tests/asm/test_all.s`：逐条对应原机器码，**裸偏移换成符号标签**，8 个测试组带完整注释。
`tests/asm/Makefile`：`make` 一键 `as` → `objcopy` → `od` → hex。

### 3.3 一个自己引入又修掉的 bug

第一版 `test_all.s` 的 `bl`/`jirl` 测试段写错了——原程序的证据值 `$sp=1` 是设在
**`bl` 的跳转目标里**，我一开始放在了返回路径上（永不执行）。

**仿真直接定位**：

```
== RESULT: FAIL —— LED 错误码=00000707（组号=7 项号=7）
```

错误码编码为「组号<<8 | 项号」，`0x0707` 精确指向组 7 项 7，一望即知。修正后 PASS。

> 这正是「测试程序自带错误码定位」的价值：**把「程序不对」变成「第 N 组第 M 项不对」**。

---

## 4. 等价性判据（重要方法论）

新汇编源经 `binutils` 生成的 hex，与原手工 hex **有 243/252 处机器码不同**。这不代表出错，
原因是**伪指令展开形式不同**：

| 源码 | 本工具链展开 | 原 hex |
|------|--------------|--------|
| `li.w $s3, 0` | `or $s3, $zero, $zero`（`0x0015001A`） | `addi.w $s3, $zero, 0`（`0x0280001A`） |

**两者语义等价**。因此判据不能是「机器码逐字节相同」，而应是**行为等价**：

```bash
# 判据：MMIO 写序列逐笔一致
iverilog -s tb_all -o tb_all.out <rtl/*.v> <tb_all.v>
vvp tb_all.out
```

实测结果（新旧程序**完全一致**）：

| # | 地址 | 数据 | 含义 |
|---|------|------|------|
| 0 | `d0000000` | `ffffffff` | LED 全亮 |
| 1 | `d000000c` | `ffffffff` | 数码管全位选 |
| 2 | `d0000004` | `0000007f` | 段选 "8" |
| 3 | `d0000008` | `0000007f` | 段选 "8" |

> **可复用的结论**：验证「改写是否等价」时，**盯外部可观测行为**（MMIO 写序列、最终状态），
> 而不是内部实现细节（具体机器码、伪指令展开形式）。

---

## 5. 最终验证结果

| 环节 | 结果 |
|------|------|
| iverilog 仿真 | ✅ PASS —— 46 条指令全部通过 |
| Vivado 综合 | ✅ `$readmem` 读入成功；`does not have driver` 0 条 |
| 实现时序 | ✅ All user specified timing constraints are met |
| 上板实测 | ✅ **LED 16 位全亮 + 数码管 8 位显示 "8"** |

---

## 6. 经验清单（下次直接查）

| # | 坑 | 症状 | 判据 / 解法 |
|---|----|------|-------------|
| 1 | `$readmemh` 路径以**综合运行目录**为基准，且失败只报 CRITICAL WARNING | **LED 全黑**，bit 照常生成 | 综合宏 `verilog_define` 传绝对路径；日志须见 `8-3876 ... is read successfully` |
| 2 | I26 偏移是**分两段** `{instr[9:0], instr[25:10]}`，非连续 `[25:0]` | 分支跳飞 | 对照 binutils 实测：`b +16` 应为 `0x50001000` |
| 3 | 改 hex 内容后不重跑综合 | 程序没变 | 必须 `reset_run synth_1` |
| 4 | `as` 加 `-march=la32rv1.0 -mabi=ilp32s` | `未识别的选项` | 直接 `as -o out.o in.s` |
| 5 | `lu12i.w` 立即数**带符号** | `Immediate overflow` | `0xD0000` 写成 `-196608` |
| 6 | `objdump` 反汇编裸二进制 | `can't use supplied machine` | 用 `-m loongarch64 -EL`，非 `loongarch:la32` |
| 7 | 只凭「日志有报错」就断定是症状根因 | 修完症状依旧 | **日志报错 ≠ 就是这个症状的原因**，须继续验证 |
| 8 | 用机器码逐字节比对判断「改写是否等价」 | 误判为不一致 | 判据用**行为等价**（MMIO 序列） |

---

## 7. 遗留事项

1. **`rtl_single_cycle/` 与 `cpu_single/` 已分叉**：工程实际使用的 `cpu_single/` 内有 3 处
   与 git 跟踪的源码目录不同（`regfile.v` 的写穿透旁路、`imem.v` 的 `IMEM_FILE` 默认值、
   `cpu_board.v` 的 `CLK_DIV`），本次修复的 `cpu_top.v` I26 解码也只在 `cpu_single/` 里。
   **照仓库重建工程会带出旧 bug**，待同步。
2. **`test_prog.hex`（23 行残缺旧版）已删除**；`sim_1/test_all.hex` 已替换为新版。
3. **演示效果待改进**：当前程序跑完即 `b 0` 停机，LED 全亮与「没跑起来」视觉不可区分，
   且无周期数/性能展示（DESIGN.md §5 规划了数码管显示周期数 + 拨码开关切换优化）。
4. **复位极性待核实**：`cpu_board.v` 注释提到「按板实测改为 `~sys_rst_n`」，但代码未取反。
   本次上板正常，故暂未改动，但该注释与代码不一致，应澄清。
