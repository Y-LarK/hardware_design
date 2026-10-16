# 构建与工程管理

> 建立日期：2026-10-16
> 适用：单周期 CPU（`rtl_single_cycle/`）
> 环境：本机 Fedora 44 + Vivado 2023.2；队友 Windows + Vivado 2019.1

本文说明**仓库怎么组织、工程怎么建、代码怎么跑起来**。设计决策见 [DESIGN.md](DESIGN.md)，踩坑记录见 [DEBUG_LOG.md](DEBUG_LOG.md)。

---

## 1. 一条铁律：仓库只存「源」，不存「工程」

`.xpr` 工程文件**永远不进 git**，三个硬性原因：

| 原因 | 说明 |
|------|------|
| 版本单向升级 | Vivado 只能「新开旧」。2023.2 保存过的 `.xpr`，**2019.1 永远打不开**；反之 2019.1 的工程被 2023.2 打开后强制升级，升级完队友又打不开 |
| 绝对路径 | `.xpr` 记录创建机器的路径（`C:/Users/...` vs `/home/ylk/...`），换机器即失效 |
| 跨 OS 分隔符 | Windows `\` 与 Linux `/` 混在工程描述里 |

**结论**：工程文件是「本地产物」，每人用脚本生成一次。源文件才是共享资产。

### 目录职责

```
hardware_design/
├── rtl_single_cycle/     ← 全部 RTL 源码（10 个 .v），新增模块放这里
├── constraints/          ← 工程用的 .xdc（当前仅 cpu.xdc，整个目录会被 glob 纳入）
├── sim/                  ← testbench（当前 tb_all.v，整个目录会被 glob 纳入）
├── tests/
│   ├── asm/              ← test_all.s（汇编源）+ Makefile
│   └── hex/              ← test_all.hex（由 asm 的 make 生成，勿手工改）
├── scripts/              ← 构建脚本（见 §3）
├── design/               ← 文档
├── cpu_single/           ← 【工程容器】本地产物，不进 git
└── out/                  ← 【构建输出】本地产物，不进 git
```

---

## 2. 两条构建路径

本项目提供**两条**互不冲突的路径，用途不同：

| | 工程模式（GUI） | 非工程模式（脚本） |
|---|---|---|
| **入口** | `cpu_single/cpu_single.xpr` | `scripts/build.sh` |
| **适合** | 看波形、单步调试、改约束 | 快速出 bit、上板 |
| **速度** | 慢（GUI 启动 + 交互） | 快（纯批处理） |
| **产物** | `cpu_single.runs/impl_1/cpu_board.bit` | `out/cpu_board.bit` |
| **读的源码** | `rtl_single_cycle/`（引用式） | `rtl_single_cycle/`（glob） |

> 两条路读的是**同一份源码**，逻辑等价。**别混用产物**——`scripts/program.tcl` 烧的是 `out/cpu_board.bit`。

---

## 3. 脚本清单

| 脚本 | 用途 | 何时用 |
|------|------|--------|
| `create_project.tcl` / `.bat` | 生成 / **增量同步** `.xpr` 工程 | 换机器、队友首次拉代码、增删 `.v` 后 |
| `build.tcl` | 非工程模式：综合→实现→bit | 上板前 |
| `build.sh` / `.bat` | 上面两个的封装，一键 | 日常构建、烧录 |
| `program.tcl` | 烧录 bit 到开发板 | 上板 |

### 3.1 首次上手（队友或换机器）

```bash
# Linux
vivado -mode batch -source scripts/create_project.tcl

# Windows：双击 scripts\create_project.bat
```

生成 `cpu_single/cpu_single.xpr`，之后用 GUI 打开即可。

### 3.2 日常开发

```bash
# 1. 改代码（引用式，改完立即生效，无需在 Vivado 里重新 Add）
vim rtl_single_cycle/alu.v

# 2. 跑仿真看 PASS/FAIL 与波形 → 开 GUI
vivado cpu_single/cpu_single.xpr
#    Flow Navigator → Simulation → Run Simulation → Run Behavioral Simulation

# 3. 上板（构建 + 烧录）
./scripts/build.sh program
```

### 3.3 改测试程序（**两步链，容易出错**）

汇编源与 Vivado 之间隔着一次转换，**Vivado 看不到 `.s`**：

```
tests/asm/test_all.s   ← 你手写的汇编源（GNU as 语法）
        │  make -C tests/asm
        ▼
tests/hex/test_all.hex ← Vivado 唯一认的（$readmemh 装载）
```

```bash
vim tests/asm/test_all.s
make -C tests/asm          # ← 忘了这步，Vivado 跑的还是旧程序，且无任何提示
```

`build.sh` 已包含 `make`，用脚本构建时无需手动执行。

**改了 hex 之后，工程模式必须 Reset 综合**（Vivado 不感知 hex 内容变化）：

```
Flow Navigator → SYNTHESIS → Reset Synthesis Run → Run Synthesis
```

> ⚠️ **不要把 `.s` 加进 Vivado 工程**。曾试过以便在 GUI 里查阅，结果 Vivado 会拿
> **内置汇编器**去编译它（本文件是 GNU as 语法，含标签与伪指令），报
> `no such instruction` 并使仿真/综合失败。改 `file_type` 为 `Document` 不被支持，
> 设 `is_enabled=false` 对 `sim_1` 也无效。要看汇编源，直接用编辑器打开即可。
>
> 若已误加并导致失败：从工程移除该文件后，**还要删掉仿真缓存目录**
> `cpu_single/cpu_single.sim/`（里面残留 `*_asm.prj` 会继续触发错误）。

---

## 4. 必须知道的两个坑

### 4.1 `IMEM_FILE` 宏 —— 忘了就是上板全黑

`imem.v` 靠 `$readmemh(IMEM_FILE, mem)` 装载程序。这个宏**必须设**，综合与仿真都要：

```tcl
set_property verilog_define [list IMEM_FILE=\"$abs_path/tests/hex/test_all.hex\"] \
    [get_filesets sources_1]
set_property verilog_define [list IMEM_FILE=\"$abs_path/tests/hex/test_all.hex\"] \
    [get_filesets sim_1]
```

**为什么危险**：`$readmemh` 找不到文件时 Vivado **只报 CRITICAL WARNING，bit 流照常生成**。
烧进去的是一片空 IMEM，上板表现为 **LED 全黑**，不报错、极难察觉。

**验证判据**：综合日志必须有这一行，否则本次构建作废：

```
INFO: [Synth 8-3876] $readmem data file '...' is read successfully
```

`create_project.tcl` 和 `build.tcl` 都已内置该宏，**手动建工程时容易漏掉**。

> 完整案例见 [DEBUG_LOG.md](DEBUG_LOG.md) 案例 1。

### 4.2 `create_project.tcl` 是「幂等」的，可随时重跑

脚本**能识别工程是否存在**，行为不同：

| 情况 | 行为 |
|------|------|
| 工程**不存在** | 新建工程（引用式挂源） |
| 工程**已存在** | **增量同步**：补加缺失文件、移除失效引用，**不重建** |

所以你在 GUI 里的设置（加到波形窗口的信号、自定义仿真时长、布局）**不会丢**。

```
========== 工程已存在，增量更新 ==========
  - 移除失效引用 old_module.v
  + 新增 new_module.v
  共补加 1 个文件
```

**新增或删除 `.v` 之后，重跑一次脚本即可同步**——不必在 GUI 里手动 Add/Remove。这是比手动操作更省事的做法。
（若只想加一个文件、不想跑脚本，在 GUI 里 `Add Sources` 也行。）

---

## 5. 工作流程示意图

```
        rtl_single_cycle/*.v  ←── 唯一真源，改这里
        constraints/cpu.xdc
        sim/tb_all.v
        tests/hex/test_all.hex
                 │
       ┌─────────┴──────────┐
       │                    │
   工程模式              非工程模式
   create_project.tcl    build.tcl
       │                    │
   cpu_single.xpr        out/cpu_board.bit
       │                    │
   GUI 仿真/看波形          program.tcl
       │                    │
       └────────► EGO1 开发板 ◄────┘
```

---

## 6. 常见问题

**Q：队友能直接用我的 `.xpr` 吗？**
不能。Vivado 版本单向升级（2023.2 → 2019.1 打不开）。他必须用自己的 Vivado 跑一次 `create_project`。

**Q：改了 RTL，工程里要重新 Add 吗？**
不用。工程是**引用式**（`$PPRDIR/../rtl_single_cycle/*.v`），改文件立即生效。

**Q：新增（或删除）了一个 `.v` 模块，工程里不同步？**
重跑 `create_project.tcl` 即可——它是幂等的，会自动补加新文件、移除失效引用，且**不重建工程、不丢 GUI 设置**（见 §4.2）。
**非工程模式本就不受影响**——`build.tcl` 用 `glob` 每次重扫目录，增删自动生效。

**Q：仿真跑起来只有 1000ns 就结束了？**
GUI 里点 **Run All** 即可（默认只跑 1000ns，本程序需约 4500ns 才出结果）。

**Q：`cpu_single/` 和 `out/` 要不要提交？**
都不提交，`.gitignore` 已忽略。

**Q：改了汇编源，Vivado 里却没变化？**
两步链：`.s` 要 `make` 成 `.hex`，工程模式还要 **Reset Synthesis Run** 重新装载。
详见 §3.3。

---

## 7. 版本兼容约束（写代码时遵守）

- `xc7a35t` 在 Vivado 2019.1 即完整支持，器件无障碍
- RTL 统一用 **Verilog-2001 / 常用 SystemVerilog 子集**，避免 2019.1 不支持的过新语法
- XDC 基于 Tcl，两版本语法通用
- **源码编码**：现有 `.v` 的中文注释是 **GBK**（Windows 侧创建），Linux 下直看是乱码。git 按字节存储不受影响，但**跨平台编辑时注意别让编辑器整体转码**（会造成全文件 diff）；新写文件统一 **UTF-8**
- 用 `grep` 查 GBK 文件会当二进制处理，改用 `python3` 读取或 `iconv -f gbk`
