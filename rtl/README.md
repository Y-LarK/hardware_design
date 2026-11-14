# rtl/ —— 流水线 CPU 源码（当前主线）

单周期版本已归档到 `archive/single_cycle/`，只作为性能对比基线，不再开发。

## 目录约定

```
rtl/
├── *.v                     ← 流水线 RTL 扁平放这里（glob 自动纳入工程/构建）
│                             新增模块直接放，脚本无需改动
└── pipeline/constraints/   ← 流水线专属约束（如 clk.xdc）
                              共享引脚约束在仓库根的 constraints/pins.xdc
```

## 构建

```bash
./scripts/sim.sh               # 批处理仿真（默认 pipeline）
./scripts/build.sh             # 综合 + 实现 + 比特流 -> out/pipeline/
./scripts/build.sh program     # 构建并烧录
vivado -mode batch -source scripts/create_project.tcl   # 生成 GUI 工程
```

## 尚未开始

流水线 RTL 还没有落地。在本目录放入第一个 `.v` 之前，
`-design pipeline` 的脚本会明确报错，不会静默生成空工程。
设计方案见 `design/DESIGN.md` §3.3~§3.6。
