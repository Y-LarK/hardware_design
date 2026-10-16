# ============================================================================
# build.tcl —— 单周期 CPU 非工程模式构建（综合 -> 实现 -> 比特流）
# ----------------------------------------------------------------------------
# 用法（Linux）：
#   vivado -mode batch -source scripts/build.tcl
# 用法（Windows）：
#   双击 scripts/build.bat
#
# 为什么用「非工程模式」而不是 .xpr 工程（见 DESIGN.md §6.1）：
#   1. 工程模式必须逐个 add_files，且新增 .v 后要重新 Add（Vivado 存的是文件
#      列表快照，不是目录监控）——本项目源码目录会持续新增文件，很烦
#   2. .xpr 记录了绝对路径与 Vivado 版本，跨机器（Linux/Windows、2023.2/2019.1）
#      互相打不开
#   本脚本用 [glob] 每次重新读目录，**新增任何 .v 都无需改动脚本**。
#
# 产物：
#   out/cpu_board.bit        可直接烧录的比特流
#   out/*.rpt                时序 / 资源 / DRC 报告
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set root       [file normalize [file join $script_dir ..]]
cd $root

# ---- 可调参数 ----
set part    xc7a35tcsg324-1
set top     cpu_board
set rtl_dir rtl_single_cycle
set hex     $root/tests/hex/test_all.hex
set out_dir $root/out

file mkdir $out_dir

puts "========== 构建开始 =========="
puts "  工程根目录 : $root"
puts "  顶层模块   : $top"
puts "  源目录     : $rtl_dir"
puts "  程序文件   : $hex"
puts ""

# ---- 1. 读入设计 ----
# [glob] 用通配符一次读入全部 .v：新增文件自动纳入，无需修改本脚本
set rtl_files [glob -nocomplain [file join $root $rtl_dir *.v]]
if {[llength $rtl_files] == 0} {
    puts "ERROR: $rtl_dir 下没有找到任何 .v 文件"
    exit 1
}
puts "读入 RTL（[llength $rtl_files] 个文件）："
foreach f $rtl_files { puts "  [file tail $f]" }
read_verilog $rtl_files

read_xdc [file join $root constraints cpu.xdc]

# 配置存不存在由脚本保证 —— §3.5.1 的教训：$readmemh 失败只报 CRITICAL WARNING，
# bit 流照常生成，结果是空 IMEM + 上板全黑。这里显式检查，缺文件直接中止。
if {![file exists $hex]} {
    puts "ERROR: 程序文件不存在：$hex"
    puts "       请先在 tests/asm/ 下执行 make 生成"
    exit 1
}

# ---- 2. 综合 ----
# 用 -verilog_define 传 IMEM 绝对路径（与运行目录无关，见 DESIGN.md §3.5.1）
synth_design -top $top -part $part \
    -verilog_define "IMEM_FILE=\"$hex\""

# 综合后必须确认程序真的装进了 IMEM，否则后面全白做。
# 注意：Tcl 里方括号是命令替换，日志里的 [Synth 8-xxxx] 必须转义或改写，不能直接写。
puts "IMEM 装载检查：请在上方综合日志中确认存在 'read successfully' 一行；"
puts "               若出现 'could not open \\\$readmem data file' 则程序未装入，本次构建作废。"

# ---- 3. 实现 ----
opt_design
place_design
route_design

# ---- 4. 报告 ----
report_utilization    -file [file join $out_dir cpu_board_util.rpt]
report_timing_summary -file [file join $out_dir cpu_board_timing.rpt]
report_drc            -file [file join $out_dir cpu_board_drc.rpt]

# ---- 5. 生成比特流 ----
write_bitstream -force [file join $out_dir cpu_board.bit]

# ---- 6. 时序收敛判定（不收敛必须让使用者知道，不能只看"生成成功"）----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
puts ""
puts "========== 构建完成 =========="
puts "  比特流   : $out_dir/cpu_board.bit"
puts "  时序 WNS : $wns ns"
if {$wns ne "" && $wns < 0} {
    puts "  ⚠️ 时序未收敛（WNS < 0），上板可能不稳定，需降低时钟频率或优化逻辑"
}
puts "  烧录     : vivado -mode batch -source scripts/program.tcl"
puts "=============================="
