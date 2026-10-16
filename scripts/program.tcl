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

# ---- 打开硬件管理器（跨 2019.1 / 2020.1+ 兼容）----
# 【为什么不能直接写 open_hw_manager】
#   open_hw_manager / close_hw_manager 是 2020.1 才引入的新入口；在 2019.1 里
#   这两个命令不存在，直接调用会报 invalid command name 而中止烧录。
#   2019.1 的入口是老命令 open_hw / close_hw。
# 【为什么 2019.1 还要先 load_features】
#   2019.1 批处理模式下硬件功能（labtools）默认不加载，未加载时连 open_hw
#   都不存在（[info commands open_hw] 为空）。2020.1+ 已内置该功能。
#   用 catch 包住：新版没有 labtools 这个 feature 名，报错可忽略。
if {[llength [info commands open_hw_manager]] == 0 && [llength [info commands open_hw]] == 0} {
    catch {load_features labtools}
}

# 探测用哪套命令，新旧各取其一（2019.1 走 else 分支）
if {[llength [info commands open_hw_manager]] > 0} {
    set hw_open  open_hw_manager
    set hw_close close_hw_manager
} elseif {[llength [info commands open_hw]] > 0} {
    set hw_open  open_hw
    set hw_close close_hw
} else {
    puts "ERROR: 本版本 Vivado 既无 open_hw_manager 也无 open_hw，无法访问硬件"
    exit 1
}
puts "硬件管理器入口：$hw_open"
$hw_open

# 若本机没有 hw_server 在跑，Vivado 会自动拉起一个
# 【-allow_non_jtag 的版本差异】
#   2020.1+ 支持 -allow_non_jtag（允许连接非 JTAG 目标）；
#   2019.1 的 connect_hw_server 只接受 [-url] [-quiet] [-verbose]，
#   传该选项会报 Common 17-170 Unknown option 而中止。
#   这里先试带选项的写法，失败再退回到不带选项，两边都能用。
if {[catch {connect_hw_server -allow_non_jtag} err]} {
    if {[catch {connect_hw_server} err2]} {
        puts "ERROR: 无法连接 hw_server：$err2"
        puts "       检查板子是否插好、USB 是否被占用：lsusb | grep 0403:6010"
        exit 1
    }
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

$hw_close
