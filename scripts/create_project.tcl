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
# 【重要】本脚本是幂等的：工程不存在则新建；已存在则**增量同步**
#   （补加缺失文件、移除失效引用），**不重建、不丢 GUI 设置**。
#   所以新增或删除 .v 之后，随时重跑本脚本同步即可。
#
# 【注意】汇编源 tests/asm/test_all.s **故意不加入工程** —— Vivado 会用
#   内置汇编器编译它并报错（详见文件末尾说明）。
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

# ---- 关于汇编源 $asm：**故意不加入工程** ----
# 曾尝试把 tests/asm/test_all.s 挂进工程供 GUI 查阅，但 Vivado 会把它当作
# ASM 源**用内置汇编器编译**（本文件是 GNU as 语法，报 no such instruction），
# 导致仿真/综合直接失败；改 file_type 为 Document 不被支持，设 is_enabled=false
# 对 sim_1 也无效。因此不再加入工程——需要看汇编源时，用编辑器打开
# tests/asm/test_all.s 即可。
#
# 切记：$readmemh 装载的是 $hex 而非 $asm。改了 .s 必须在 tests/asm/ 下
# make 重新生成 hex，否则综合/仿真用的仍是旧程序，且不会有任何提示。

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
