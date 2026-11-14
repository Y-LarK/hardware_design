# ============================================================================
# build.tcl —— 非工程模式构建（综合 -> 实现 -> 比特流）
# ----------------------------------------------------------------------------
# 用法（Linux）：
#   vivado -mode batch -source scripts/build.tcl                     # 默认 pipeline
#   vivado -mode batch -source scripts/build.tcl -tclargs single     # 单周期基线
# 用法（Windows）：
#   scripts\build.bat            (默认 pipeline)
#   scripts\build.bat single     (单周期基线)
#
# 为什么用「非工程模式」而不是 .xpr 工程（见 design/DESIGN.md §6.1）：
#   1. 工程模式必须逐个 add_files，且新增 .v 后要重新 Add（Vivado 存的是文件
#      列表快照，不是目录监控）——本项目源码目录会持续新增文件，很烦
#   2. .xpr 记录了绝对路径与 Vivado 版本，跨机器（Linux/Windows、2023.2/2019.1）
#      互相打不开
#   本脚本用 [glob] 每次重新读目录，**新增任何 .v 都无需改动脚本**。
#
# 产物：out/<design>/ 下
#   cpu_board.bit      可直接烧录的比特流（program.tcl 读它）
#   *.rpt              时序 / 资源 / DRC 报告
# 两套设计产物分目录，避免单周期与流水线的 bit 互相覆盖。
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set root       [file normalize [file join $script_dir ..]]
cd $root

# ---- 可调参数 ----
set part xc7a35tcsg324-1

# ---- 设计映射表（唯一事实来源，与 create_project.tcl 同构）----
# 改目录只改这张表；两处必须保持一致，否则 GUI 工程与非工程模式读的源码不同。
set DESIGNS [dict create \
    single [dict create \
        rtl_dir    [file join $root archive single_cycle rtl] \
        constr_dirs [list [file join $root constraints] \
                          [file join $root archive single_cycle constraints]] \
        top        cpu_board] \
    pipeline [dict create \
        rtl_dir    [file join $root rtl] \
        constr_dirs [list [file join $root constraints] \
                          [file join $root rtl pipeline constraints]] \
        top        cpu_pipeline_board]]

# ---- 解析 -design（默认 pipeline）----
set design pipeline
if {[llength $argv] > 0 && [lindex $argv 0] ne ""} {
    set design [lindex $argv 0]
}
if {![dict exists $DESIGNS $design]} {
    puts "ERROR: 未知设计名 '$design'"
    puts "       可用值：[join [lsort [dict keys $DESIGNS]] { / }]"
    exit 1
}
set cfg [dict get $DESIGNS $design]

set top         [dict get $cfg top]
set rtl_dir     [dict get $cfg rtl_dir]
set constr_dirs [dict get $cfg constr_dirs]
# 当前程序：改测试程序时**必须**同步改这里和 create_project.tcl 的 $hex，
# 以及 tests/asm/Makefile 的 SRC/HEX —— 只改汇编源不会自动生效（见 DESIGN.md §3.5.1）
set hex         [file join $root tests/hex/test_all.hex]
set out_dir     [file join $root out $design]

file mkdir $out_dir

puts "========== 构建开始（$design）=========="
puts "  工程根目录 : $root"
puts "  顶层模块   : $top"
puts "  源目录     : $rtl_dir"
puts "  程序文件   : $hex"
puts ""

# ---- 1. 读入设计 ----
# [glob] 用通配符一次读入全部 .v：新增文件自动纳入，无需修改本脚本
set rtl_files [glob -nocomplain [file join $rtl_dir *.v]]
if {[llength $rtl_files] == 0} {
    puts "ERROR: $rtl_dir 下没有找到任何 .v 文件"
    if {$design eq "pipeline"} {
        puts "       流水线版本尚未开始，先把 RTL 放进 rtl/ 再来。"
        puts "       只想构建单周期基线请用：-tclargs single"
    }
    exit 1
}
puts "读入 RTL（[llength $rtl_files] 个文件）："
foreach f $rtl_files { puts "  [file tail $f]" }
read_verilog $rtl_files

# 约束同样按设计 glob：共享 pins.xdc + 本设计专属约束（如时钟）。
# 注意：目录下**所有** .xdc 都会生效，官方全量参考约束请放 constraints/ 之外。
set xdc_files {}
foreach d $constr_dirs {
    set xdc_files [concat $xdc_files [glob -nocomplain [file join $d *.xdc]]]
}
puts "读入约束（[llength $xdc_files] 个文件）："
foreach f $xdc_files { puts "  [file tail $f]" }
read_xdc $xdc_files

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
report_utilization    -file [file join $out_dir util.rpt]
report_timing_summary -file [file join $out_dir timing.rpt]
report_drc            -file [file join $out_dir drc.rpt]

# ---- 5. 生成比特流 ----
write_bitstream -force [file join $out_dir cpu_board.bit]

# ---- 6. 时序收敛判定（不收敛必须让使用者知道，不能只看"生成成功"）----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
puts ""
puts "========== 构建完成（$design）=========="
puts "  比特流   : $out_dir/cpu_board.bit"
puts "  时序 WNS : $wns ns"
if {$wns ne "" && $wns < 0} {
    puts "  ⚠️ 时序未收敛（WNS < 0），上板可能不稳定，需降低时钟频率或优化逻辑"
}
puts "  烧录     : vivado -mode batch -source scripts/program.tcl -tclargs $design"
puts "======================================"
