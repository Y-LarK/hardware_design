# ============================================================================
# clk.xdc —— 单周期 CPU 时钟约束（archive/single_cycle）
# ----------------------------------------------------------------------------
# 【为何单独成文件】
#   create_generated_clock 的 divide_by 与 cpu_board.v 的 CLK_DIV 强绑定：
#   CLK_DIV=100 -> 每 100 个 sys_clk 翻转一次 -> 完整周期 200 个 sys_clk。
#   流水线的时钟方案不同（目标 100 MHz 直连），不能共用一个约束文件，
#   否则改一边会同时影响另一边。
#
# 【必须同步修改的一对】
#   archive/single_cycle/rtl/cpu_board.v  parameter CLK_DIV = 100
#   本文件                                -divide_by 200      (= 2*CLK_DIV)
#   改了 CLK_DIV 而忘了这里，时序分析会按错的时钟做，收敛结论失真。
#
# 【注意】XDC 不支持 if/set 等 Tcl 控制语句（会报 Designutils 20-1307），
#   所以这里不做条件守卫，只能靠上面这对手工同步。
# ============================================================================

# ---- 时钟约束：100 MHz ----
create_clock -period 10.000 -name sys_clk [get_ports sys_clk_in]

# ---- CPU 分频时钟：cpu_board.v 的 cpu_clk 由 sys_clk 翻转得到 ----
# 每 CLK_DIV 个 sys_clk 周期翻转一次，完整周期 = 2*CLK_DIV 个 sys_clk 周期。
# divide_by 必须与 cpu_board.v 的 CLK_DIV 同步：CLK_DIV=100 -> divide_by 200。
# 注意：XDC 不支持 if/set 等 Tcl 控制语句（会报 Designutils 20-1307），
# 所以这里不做条件守卫；CLK_DIV 改动时须同步修改下面的 divide_by。
create_generated_clock -name cpu_clk -source [get_ports sys_clk_in] -divide_by 200 [get_pins cpu_clk_reg/Q]
