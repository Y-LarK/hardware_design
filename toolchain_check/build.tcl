# ============================================================
# Vivado 非工程批处理脚本：综合 -> 实现 -> 生成比特流
# 用法: vivado -mode batch -source build.tcl
# ============================================================

set part xc7a35tcsg324-1
set top  led_blink

# 读入设计
read_verilog ${top}.v
read_xdc     ego1_min.xdc

# 综合
synth_design -top ${top} -part ${part}

# 实现
opt_design
place_design
route_design

# 生成比特流
write_bitstream -force ${top}.bit

# 报告
report_utilization    -file ${top}_util.rpt
report_timing_summary -file ${top}_timing.rpt
report_drc            -file ${top}_drc.rpt

puts "=================== 流程完成 ==================="
puts "比特流: ${top}.bit"
puts "资源报告: ${top}_util.rpt"
puts "时序报告: ${top}_timing.rpt"
puts "DRC 报告: ${top}_drc.rpt"
puts "================================================"
