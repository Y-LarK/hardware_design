# ============================================================================
# simulate.tcl —— 批处理方式跑行为仿真（不开 GUI），用于快速回归
# ----------------------------------------------------------------------------
# 用法：vivado -mode batch -source scripts/simulate.tcl
# 前置：已用 create_project.tcl 生成过工程
#
# 与 GUI 仿真的关系：
#   - GUI 看波形  ：打开 .xpr -> Flow Navigator -> Run Simulation（推荐日常调试）
#   - 本脚本      ：只需 PASS/FAIL 结论时用，比开 GUI 快，适合改完代码先自查
#
# 注意：批处理模式下仿真**不会自动跑到底**，必须显式 `run <时长>`，
#       否则默认只跑 1000ns 就结束（本程序需约 4500ns 才出结果）。
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set root       [file normalize [file join $script_dir ..]]
set xpr        [file join $root cpu_single cpu_single.xpr]

if {![file exists $xpr]} {
    puts "ERROR: 工程不存在：$xpr"
    puts "       请先运行：vivado -mode batch -source scripts/create_project.tcl"
    exit 1
}

open_project $xpr
launch_simulation -mode behavioral

# 显式运行时长方能让程序跑完（程序在约 4500ns 处出结果）
run 20000ns

close_sim
close_project

puts ""
puts "提示：如需看波形，请用 Vivado GUI 打开 cpu_single/cpu_single.xpr，"
puts "      Flow Navigator -> Simulation -> Run Simulation -> Run Behavioral Simulation"
