# ============================================================================
# program.tcl —— 把比特流烧录到 EGO1（xc7a35tcsg324-1）
# ----------------------------------------------------------------------------
# 用法：vivado -mode batch -source scripts/program.tcl
# 前置：out/cpu_board.bit 已由 build.tcl 生成
#
# 硬件连接（已实测，2026-10-15）：
#   板载 JTAG 芯片 FTDI FT2232H（USB ID 0403:6010），hw_target 形如
#   localhost:3121/xilinx_tcf/Xilinx/1234-tulA，器件 xc7a35t_0
#   udev 规则已装（/etc/udev/rules.d/52-xilinx-ftdi-usb.rules），普通用户即可烧录
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set root       [file normalize [file join $script_dir ..]]
set bit        [file join $root out cpu_board.bit]

if {![file exists $bit]} {
    puts "ERROR: 比特流不存在：$bit"
    puts "       请先运行：vivado -mode batch -source scripts/build.tcl"
    exit 1
}

open_hw_manager

# 若本机没有 hw_server 在跑，Vivado 会自动拉起一个
if {[catch {connect_hw_server -allow_non_jtag} err]} {
    puts "ERROR: 无法连接 hw_server：$err"
    puts "       检查板子是否插好、USB 是否被占用：lsusb | grep 0403:6010"
    exit 1
}

set targets [get_hw_targets]
if {[llength $targets] == 0} {
    puts "ERROR: 未发现 JTAG 目标。检查板子电源与 USB 连接。"
    exit 1
}
puts "发现 JTAG 目标："
foreach t $targets { puts "  $t" }

open_hw_target [lindex $targets 0]
set dev [lindex [get_hw_devices] 0]
puts "识别到器件：$dev"

current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "========== 烧录完成 =========="
puts "  比特流：$bit"
puts "  器件  ：$dev"
puts "=============================="

close_hw_manager
