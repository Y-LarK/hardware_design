# ============================================================================
# create_project.tcl —— 一键创建 Vivado 工程（供 GUI 仿真 / 看波形用）
# ----------------------------------------------------------------------------
# 用法（Linux）：
#   vivado -mode batch -source scripts/create_project.tcl
# 用法（Windows）：
#   双击 scripts/create_project.bat
#
# 生成：cpu_single/cpu_single.xpr —— 之后用 Vivado GUI 打开它即可
#
# 【为什么需要这个脚本】
# Vivado 工程文件（.xpr）**不能进 git**，原因（详见 DESIGN.md §6.1）：
#   1. 版本单向升级：2023.2 建的工程，2019.1 永远打不开（反之亦然）
#   2. .xpr 记录创建机器的绝对路径，换机器即失效
#   3. Windows 与 Linux 的路径分隔符不同
# 因此约定：**仓库只存源文件，工程各人用本脚本自动生成一次**。
#
# 【本脚本做的事】
#   1. 引用式加源（不拷贝，改源文件立即生效）
#   2. 加 testbench 与 hex 到 sim_1（仿真需要）
#   3. 设 IMEM_FILE 宏（综合与仿真都要，否则 imem 装配不到程序）
#   4. 指定顶层
#
# 【重要】每次新增 .v 文件后，重跑本脚本即可（加 -force 会重建工程）；
#   轻量做法：在 GUI 里 Add Sources 手动加上那一个文件。
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set root       [file normalize [file join $script_dir ..]]
cd $root

set proj_dir [file join $root cpu_single]
set proj_name cpu_single
set part     xc7a35tcsg324-1

set hex [file join $root tests/hex/test_all.hex]
if {![file exists $hex]} {
    puts "ERROR: 程序文件不存在：$hex"
    puts "       请先在 tests/asm/ 下执行 make 生成"
    exit 1
}

set xpr [file join $proj_dir $proj_name.xpr]
set exists [file exists $xpr]

if {$exists} {
    # ---- 工程已存在：增量补加，不重建 ----
    # 重建（create_project -force）会丢掉 GUI 里的手动设置：
    # 加到波形窗口的信号、自定义仿真时长、波形布局等。
    # 这里改为「打开 + 只补缺失的文件」，改代码/加新文件都不丢设置。
    puts "========== 工程已存在，增量更新 =========="
    puts "  位置: $xpr"
    open_project $xpr

    # ---- 先清理：工程里引用了、但磁盘上已不存在的文件 ----
    # 队友删掉某个模块后，若不清理，综合会因找不到文件而报错。
    set removed 0
    foreach f [get_files -quiet] {
        if {![file exists $f]} {
            puts "  - 移除失效引用 [file tail $f]"
            remove_files -quiet $f
            incr removed
        }
    }
    if {$removed > 0} { puts "  共移除 $removed 个失效引用" }

    # ---- 再补加：磁盘上有、但工程里还没登记的文件 ----
    set have {}
    foreach f [get_files -quiet] {
        if {[file exists $f]} { lappend have [file normalize $f] }
    }
    proc add_missing {files fileset} {
        global have
        set added 0
        foreach f $files {
            set n [file normalize $f]
            if {[lsearch -exact $have $n] < 0} {
                add_files -norecurse -fileset $fileset $f
                lappend have $n
                puts "  + 新增 [file tail $f]"
                incr added
            }
        }
        return $added
    }
    set n1 [add_missing [glob -nocomplain [file join $root rtl_single_cycle *.v]] sources_1]
    set n2 [add_missing [list [file join $root constraints cpu.xdc]] constrs_1]
    set n3 [add_missing [list [file join $root sim tb_all.v] $hex] sim_1]
    puts "  共补加 [expr {$n1+$n2+$n3}] 个文件"
} else {
    # ---- 工程不存在：新建 ----
    puts "========== 新建工程 =========="
    puts "  位置: $xpr"
    create_project $proj_name $proj_dir -part $part

    # 1. RTL（引用式，不拷贝进工程）
    add_files -norecurse [glob -nocomplain [file join $root rtl_single_cycle *.v]]
    # 2. 约束
    add_files -norecurse -fileset constrs_1 [file join $root constraints cpu.xdc]
    # 3. testbench 与 hex（sim_1 文件集）
    add_files -norecurse -fileset sim_1 [file join $root sim tb_all.v]
    add_files -norecurse -fileset sim_1 $hex
}

# ---- IMEM_FILE 宏（两种路径都要设）----
# 综合与仿真都必须设：imem.v 靠它找到程序文件。
# 不设的后果见 DESIGN.md §3.5.1 —— $readmemh 失败只报警告，bit 照常生成，
# 但 IMEM 是空的，上板表现为全黑。
# 用绝对路径，与「运行目录」无关。
foreach fs {sources_1 sim_1} {
    set_property verilog_define [list IMEM_FILE=\"$hex\"] [get_filesets $fs]
}

# ---- 5. 顶层 ----
set_property top cpu_board [get_filesets sources_1]
set_property top tb_all    [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "========== 完成 =========="
puts "  RTL 文件 : [llength [get_files -of [get_filesets sources_1]]] 个"
puts "  仿真文件 : [llength [get_files -of [get_filesets sim_1]]] 个"
puts "  工程文件 : $proj_dir/$proj_name.xpr"
puts ""
puts "  下一步：用 Vivado GUI 打开该 .xpr"
puts "    - 看波形：Flow Navigator -> Simulation -> Run Simulation -> Run Behavioral"
puts "    - 综合实现：Flow Navigator -> Synthesis / Implementation"
puts "=========================="

close_project
