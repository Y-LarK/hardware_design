# CLAUDE.md

本文件为 Claude Code 在本仓库中工作的项目约定。所有说明应以当前源码和脚本为准；遇到冲突时，先核对实现并更新文档，不要凭旧设计计划推断当前代码。

## 项目概况

- 当前可综合设计是 LoongArch LA32R 单周期 CPU，RTL 在 `rtl_single_cycle/`，开发板顶层为 `cpu_board`。
- 目标板为 EGO1 / Xilinx Artix-7 `xc7a35tcsg324-1`。Vivado 版本存在跨机器差异（2023.2 与 2019.1），避免依赖较新版本才支持的语法或 Tcl 特性。
- 仓库保存源码和可复现构建脚本，不保存 Vivado 工程及构建产物。
- `design/DESIGN.md` 含较长期的流水线 CPU 目标和设计方案；不要把规划内容误认为已实现功能。当前实现及构建方式以 `rtl_single_cycle/`、`scripts/` 和 `design/BUILD.md` 为准。

## 目录与职责

| 路径                  | 内容                                                             |
| --------------------- | ---------------------------------------------------------------- |
| `rtl_single_cycle/`   | CPU RTL 模块；新增 RTL 模块放在这里                              |
| `constraints/`        | Vivado XDC 约束；`cpu.xdc` 用于当前 CPU 顶层                     |
| `sim/`                | Verilog testbench                                                |
| `tests/asm/`          | GNU LoongArch 汇编测试源及 Makefile                              |
| `tests/hex/`          | `$readmemh` 使用的程序镜像；由汇编源生成，构建所需且纳入版本控制 |
| `scripts/`            | Vivado Tcl、Linux 和 Windows 构建/烧录脚本                       |
| `design/`、`doc/`     | 设计、构建、调试文档及参考资料                                   |
| `out/`、`cpu_single/` | 本机构建输出或 Vivado GUI 工程，不提交                           |

## 编码与 RTL 规范

- 新增文本文件统一使用 UTF-8。仓库部分旧 `.v`/`.xdc` 含 GBK 注释；编辑时保持原编码和行尾，避免整文件转码造成无关 diff。不要顺手批量“修复”乱码。
- RTL 使用 Verilog-2001 和 Vivado 2019.1 可用的语法子集；除非项目明确升级工具链，不要引入依赖新版本的 SystemVerilog 特性。
- 模块使用显式端口列表，信号名采用小写下划线风格；位宽写明，常量带明确位宽，避免隐式截断/扩展。
- 组合逻辑使用 `always @(*)` 和阻塞赋值；过程块给所有输出完整赋默认值，避免锁存器。时序逻辑使用非阻塞赋值。
- 保持复位极性、同步方式和时钟行为与现有模块一致；当前 CPU 内部复位为低有效 `rst_n`。不要在局部重构中改变板级接口或时钟分频约定。
- 指令字段、立即数扩展、分支/跳转偏移、访存宽度和 MMIO 地址都属于体系结构行为。修改解码或数据通路时，先查阅 `design/DESIGN.md` 和相关模块，再同步更新汇编用例/镜像与文档。
- `imem.v` 通过 `IMEM_FILE` 宏装载程序。Vivado 构建必须保留该宏和有效的 `tests/hex/test_all.hex` 输入；不要把 `.s` 文件加入 Vivado 工程，GNU 汇编源应先生成 hex。
- 新增 RTL 文件放进 `rtl_single_cycle/`，`scripts/build.tcl` 会扫描该目录的 `.v` 文件。若使用 GUI 工程，运行 `scripts/create_project.tcl` 同步工程源文件。
- 不做与任务无关的重排、全文件格式化或接口重命名，便于 review 并避免跨平台编码差异。

## Git 规范

- 提交信息遵循 Conventional Commits：`<type>: <中文摘要>`，例如 `fix: 修正无符号比较边界`。常用 type：`feat`、`fix`、`refactor`、`perf`、`docs`、`test`、`chore`。
- 一次提交聚焦一件事；提交前检查 `git status`、`git diff` 和 `git diff --staged`，确认没有不相关改动或生成物。
- 小型文档/局部修复可在 `main` 上处理；新模块、大型改造或高冲突改动使用短期分支 `feat/<主题>`。不要 force push `main`。
- 提交前按协作流程同步远端：`git pull --rebase origin main`。解决冲突时逐文件检查，不要用覆盖式操作丢弃他人修改。
- 未经用户明确要求，不自动创建提交、推送、合并或改写已有提交历史；可以准备好变更供用户审阅。
- 提交源文件、RTL、约束、testbench、汇编源、必要的 `.hex`/`.mem`、脚本和文档。不要提交 `.xpr`、Vivado 缓存/运行目录、`.bit`、报告、日志或波形文件。不要用 `git add -f` 绕过 `.gitignore`。
- 新增/修改测试汇编源后，按需执行 `make -C tests/asm` 更新镜像；检查生成的 `tests/hex/test_all.hex` 差异，避免源与镜像不一致。

## 构建与仿真

### 命令

Linux：

```bash
# 构建综合、布局布线和 bitstream；脚本会先运行汇编 Makefile
./scripts/build.sh

# 构建后烧录 EGO1（需要 Vivado 和连接好的 JTAG 板卡）
./scripts/build.sh program

# 仅在修改汇编且需要检查机器码时
make -C tests/asm disasm
```

Windows 使用 `scripts/build.bat`，可传入 `program` 参数。需要 GNU LoongArch binutils（`loongarch64-linux-gnu-as`、`objcopy`、`objdump`）和 Vivado；Vivado 的 `bin` 目录需在 `PATH` 中（Linux 脚本也会尝试常见安装路径）。

- 构建入口：`scripts/build.sh` / `scripts/build.bat` → `scripts/build.tcl`。
- 构建脚本先执行 `make -C tests/asm`，然后以非工程模式读取 `rtl_single_cycle/*.v`、`constraints/cpu.xdc` 和测试 hex，目标器件为 `xc7a35tcsg324-1`，顶层为 `cpu_board`。
- 生成文件位于 `out/`，包括 `out/cpu_board.bit`、Vivado 日志和报告；它们是本地产物，不加入 Git。
- 上板前检查综合日志中 `$readmemh` 成功读取程序文件的提示。若文件不存在或装载失败，不要把“bitstream 已生成”当作构建有效。
- 不要在未确认目标板和硬件连接的情况下调用烧录命令。

### GUI 工程与批处理仿真

- `scripts/create_project.tcl`（Windows 有 `.bat` 封装）用于生成/增量更新本地 `cpu_single/cpu_single.xpr`；工程不进 Git。
- `scripts/simulate.tcl` 依赖上述 GUI 工程已创建，并运行行为仿真。修改 `tests/asm/test_all.s` 后应先运行 `make -C tests/asm`；GUI 工程模式下若程序镜像变化未被重新读取，按 `design/BUILD.md` 的说明重置综合运行。
- `sim/tb_all.v` 通过 MMIO 写序列输出 PASS/FAIL 信息。调试波形时可用 Vivado GUI 打开本地工程。

## 建议工作流程

1. 先查看 `git status` 和相关模块/文档，确认当前实现与工作区状态。
2. 只修改完成任务所需的文件，保留既有编码和接口约定。
3. 若任务要求验证，选用对应的汇编、仿真或 Vivado 构建命令，并汇报工具版本/缺失依赖及结果；不要声称未实际运行的命令已通过。
4. 最后检查 `git diff`，确认变更范围、程序镜像和文档相互一致。

## 参考文档

- `design/BUILD.md`：构建路径、Vivado 工程和汇编镜像流程。
- `design/GIT.md`：分支、提交、推拉及提交内容边界。
- `design/DESIGN.md`：指令集、数据通路、板级接口和设计决策。
- `design/DEBUG_LOG.md`：已记录的问题和调试经验。
