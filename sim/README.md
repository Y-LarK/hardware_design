# sim/ —— 流水线 CPU 的 testbench

单周期的 `tb_all.v` 已随其 RTL 归档到 `archive/single_cycle/sim/`。

本目录的 `.v` 会被 glob 纳入 `sim_1` 文件集，仿真顶层默认为 `tb_pipeline`
（见 `scripts/create_project.tcl` 的映射表）。新增 tb 直接放这里。

若只有一条 tb，命名与映射表里的 `top_sim` 保持一致，否则 xelab 找不到顶层。
