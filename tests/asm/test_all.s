/* ============================================================================
 * test_all.s —— LA32R 单周期 CPU 全指令上板自检程序
 * ----------------------------------------------------------------------------
 * 由 test_all.hex 反汇编还原（binutils 2.46.1），逐条对应原机器码。
 * 分支偏移改为符号标签，语义与原程序完全一致。
 *
 * 运行地址：程序被烧录到 IMEM 起始，实际执行的 PC 基址为 0x1C000000，
 *   故本程序在 0x1C000000 + 偏移 处运行（与 pc.v 复位值一致）。
 *   程序内部用 pcaddu12i 自测 PC 相对寻址，不依赖绝对重定位。
 *
 * 功能：遍历 10 个指令测试组，每组含若干测试项；每项算出实际结果与期望值
 *   比对，不等则跳转 FAIL。全部通过后写外设：LED 全亮、数码管显示 8 个 "8"，
 *   然后原地停机。
 *   运行过程：每通过一组点亮一位 LED（进度流水灯），失败时 LED 定格在
 *   「已通过组数」，可看出程序跑到哪里。
 *   失败时：LED = 组号<<8 | 项号；数码管位 0 显示组号数字（0..7）、
 *   位 4 显示项号数字（0..9，带小数点以便与组号区分）。
 *
 * MMIO 映射（design/DESIGN.md §4.2）
 *   0xD0000000 W led[15:0]        0xD0000004 W seg_data0[7:0]
 *   0xD0000008 W seg_data1[7:0]   0xD000000C W seg_cs[7:0]
 *
 * 寄存器约定
 *   $t7 = 0xD0000000  MMIO 基址
 *   $t8 = 0x10000000  测试数据存储区基址
 *   $t6 = 0x10000100  数字段码表（0..9 共 10 项，启动时写入 dmem；
 *                     imem/dmem 分离，无法从代码段 pc 相对取数）
 *   $ra = 10, $tp = 3 测试源操作数
 *   $sp               结果暂存
 *   $s3               当前组号 0..7
 *   $s4               当前项号
 *   $s1               外设写入暂存
 *   $s2               期望值
 *   $a0 / $a1         被跳转指令顺带验证的目标寄存器
 *
 * 构建：见同目录 Makefile
 * ============================================================================ */

    .text
    .globl _start
_start:
/* ---------------------------------------------------------------------------
 * 初始化：MMIO 基址、测试数据区、源操作数
 * -------------------------------------------------------------------------*/
    li.w      $ra, 10               /* 源操作数 A */
    li.w      $tp, 3                /* 源操作数 B */
    lu12i.w   $t7, -196608          /* $t7 = 0xD0000000  MMIO 基址
                                       lu12i.w 的 20 位立即数是带符号的，
                                       0xD0000 写作 -196608（同一编码） */
    lu12i.w   $t8, 0x10000          /* $t8 = 0x10000000  测试数据存储区 */
    lu12i.w   $t6, 0x10000          /* $t6 = 0x10000100  数字段码表基址 */
    ori       $t6, $t6, 0x100

    /* 数字段码 0..9（共阴高有效 {DP,G,F,E,D,C,B,A}）写入 dmem，供 FAIL 查表 */
    li.w      $s1, 0x3F
    st.w      $s1, $t6, 0           /* 段码[0] = 0x3F */
    li.w      $s1, 0x06
    st.w      $s1, $t6, 4           /* 段码[1] = 0x06 */
    li.w      $s1, 0x5B
    st.w      $s1, $t6, 8           /* 段码[2] = 0x5B */
    li.w      $s1, 0x4F
    st.w      $s1, $t6, 12          /* 段码[3] = 0x4F */
    li.w      $s1, 0x66
    st.w      $s1, $t6, 16          /* 段码[4] = 0x66 */
    li.w      $s1, 0x6D
    st.w      $s1, $t6, 20          /* 段码[5] = 0x6D */
    li.w      $s1, 0x7D
    st.w      $s1, $t6, 24          /* 段码[6] = 0x7D */
    li.w      $s1, 0x07
    st.w      $s1, $t6, 28          /* 段码[7] = 0x07 */
    li.w      $s1, 0x7F
    st.w      $s1, $t6, 32          /* 段码[8] = 0x7F */
    li.w      $s1, 0x6F
    st.w      $s1, $t6, 36          /* 段码[9] = 0x6F */

/* ===========================================================================
 * 组 0：算术 add.w / sub.w / addi.w
 * =========================================================================*/
    li.w      $s3, 0
    add.w     $sp, $ra, $tp         /* 10 + 3 = 13 */
    li.w      $s4, 0
    li.w      $s2, 13
    bne       $s2, $sp, FAIL

    sub.w     $sp, $ra, $tp         /* 10 - 3 = 7 */
    li.w      $s4, 1
    li.w      $s2, 7
    bne       $s2, $sp, FAIL

    addi.w    $sp, $ra, 5           /* 10 + 5 = 15 */
    li.w      $s4, 2
    li.w      $s2, 15
    bne       $s2, $sp, FAIL

    /* 进度灯：组 0 通过，LED = 0x0001，随后延迟 125ms 让流水可见 */
    li.w      $s1, 1
    st.w      $s1, $t7, 0
    li.w      $s5, 31250            /* 31250 轮 x 4us（2 指令 x 2us）= 125ms */
DELAY0:
    addi.w    $s5, $s5, -1
    bne       $s5, $zero, DELAY0

/* ===========================================================================
 * 组 1：大立即数 lu12i.w
 * =========================================================================*/
    lu12i.w   $sp, 0x12345          /* $sp = 0x12345000 */
    li.w      $s3, 1
    li.w      $s4, 3
    lu12i.w   $s2, 0x12345
    bne       $s2, $sp, FAIL

    /* 进度灯：组 1 通过，LED = 0x0003，随后延迟 125ms 让流水可见 */
    li.w      $s1, 3
    st.w      $s1, $t7, 0
    li.w      $s5, 31250            /* 31250 轮 x 4us（2 指令 x 2us）= 125ms */
DELAY1:
    addi.w    $s5, $s5, -1
    bne       $s5, $zero, DELAY1

/* ===========================================================================
 * 组 2：比较 sltu / slt / slti / sltui，含 pcaddu12i 自测 PC 相对寻址
 * =========================================================================*/
    pcaddu12i $sp, 0                /* $sp = 当前 PC（应落在 0x1C000000 段内） */
    li.w      $s3, 2
    li.w      $s4, 4
    lu12i.w   $s2, 0x1C000          /* 0x1C000000 */
    sltu      $a0, $sp, $s2         /* 当前 PC < 0x1C000000 ? -> 应为 0 */
    li.w      $s2, 0
    bne       $s2, $a0, FAIL

    lu12i.w   $s2, 0x1C001          /* 0x1C001000 */
    sltu      $a0, $sp, $s2         /* 当前 PC < 0x1C001000 ? -> 应为 1 */
    li.w      $s2, 1
    bne       $s2, $a0, FAIL

    slt       $sp, $ra, $tp         /* 10 < 3 ? -> 0 */
    li.w      $s4, 5
    li.w      $s2, 0
    bne       $s2, $sp, FAIL

    sltu      $sp, $ra, $tp         /* 10 < 3 ? -> 0 */
    li.w      $s4, 6
    li.w      $s2, 0
    bne       $s2, $sp, FAIL

    slti      $sp, $ra, 15          /* 10 < 15 ? -> 1 */
    li.w      $s4, 7
    li.w      $s2, 1
    bne       $s2, $sp, FAIL

    sltui     $sp, $ra, 5           /* 10 < 5 ? -> 0 */
    li.w      $s4, 8
    li.w      $s2, 0
    bne       $s2, $sp, FAIL

    /* 进度灯：组 2 通过，LED = 0x0007，随后延迟 125ms 让流水可见 */
    li.w      $s1, 7
    st.w      $s1, $t7, 0
    li.w      $s5, 31250            /* 31250 轮 x 4us（2 指令 x 2us）= 125ms */
DELAY2:
    addi.w    $s5, $s5, -1
    bne       $s5, $zero, DELAY2

/* ===========================================================================
 * 组 3：逻辑 and / or / nor / xor / andi / ori / xori
 * =========================================================================*/
    li.w      $s3, 3
    and       $sp, $ra, $tp         /* 10 & 3 = 2 */
    li.w      $s4, 0
    li.w      $s2, 2
    bne       $s2, $sp, FAIL

    or        $sp, $ra, $tp         /* 10 | 3 = 11 */
    li.w      $s4, 1
    li.w      $s2, 11
    bne       $s2, $sp, FAIL

    nor       $sp, $ra, $tp         /* ~(10 | 3) = -12 */
    li.w      $s4, 2
    li.w      $s2, -12
    bne       $s2, $sp, FAIL

    xor       $sp, $ra, $tp         /* 10 ^ 3 = 9 */
    li.w      $s4, 3
    li.w      $s2, 9
    bne       $s2, $sp, FAIL

    andi      $sp, $ra, 0x3         /* 10 & 3 = 2 */
    li.w      $s4, 4
    li.w      $s2, 2
    bne       $s2, $sp, FAIL

    ori       $sp, $ra, 0x100       /* 10 | 256 = 266 */
    li.w      $s4, 5
    li.w      $s2, 266
    bne       $s2, $sp, FAIL

    xori      $sp, $ra, 0xF         /* 10 ^ 15 = 5 */
    li.w      $s4, 6
    li.w      $s2, 5
    bne       $s2, $sp, FAIL

    /* 进度灯：组 3 通过，LED = 0x000F，随后延迟 125ms 让流水可见 */
    li.w      $s1, 0xF
    st.w      $s1, $t7, 0
    li.w      $s5, 31250            /* 31250 轮 x 4us（2 指令 x 2us）= 125ms */
DELAY3:
    addi.w    $s5, $s5, -1
    bne       $s5, $zero, DELAY3

/* ===========================================================================
 * 组 4：移位 sll.w / srl.w / sra.w / slli.w / srli.w / srai.w
 * =========================================================================*/
    li.w      $s3, 4
    sll.w     $sp, $ra, $tp         /* 10 << 3 = 80 */
    li.w      $s4, 0
    li.w      $s2, 80
    bne       $s2, $sp, FAIL

    srl.w     $sp, $ra, $tp         /* 10 >> 3 = 1 */
    li.w      $s4, 1
    li.w      $s2, 1
    bne       $s2, $sp, FAIL

    li.w      $a0, -1               /* $a0 = -10（0xFFFFFFF6） */
    addi.w    $a0, $a0, -9
    sra.w     $sp, $a0, $tp         /* 算术右移 3：-10 >> 3 = -2 */
    li.w      $s4, 2
    li.w      $s2, -1
    addi.w    $s2, $s2, -1          /* $s2 = -2 */
    bne       $s2, $sp, FAIL

    slli.w    $sp, $ra, 2           /* 10 << 2 = 40 */
    li.w      $s4, 3
    li.w      $s2, 40
    bne       $s2, $sp, FAIL

    li.w      $a0, -1               /* $a0 = -16（0xFFFFFFF0） */
    addi.w    $a0, $a0, -15
    srai.w    $sp, $a0, 2           /* 算术右移 2：-16 >> 2 = -4 */
    li.w      $s4, 4
    li.w      $s2, -1
    addi.w    $s2, $s2, -3          /* $s2 = -4 */
    bne       $s2, $sp, FAIL

    li.w      $a0, -1               /* $a0 = -16（0xFFFFFFF0） */
    addi.w    $a0, $a0, -15
    srli.w    $sp, $a0, 28          /* 逻辑右移 28：0xFFFFFFF0 -> 0xF（算术右移会得 -1） */
    li.w      $s4, 5
    li.w      $s2, 15
    bne       $s2, $sp, FAIL

    /* 进度灯：组 4 通过，LED = 0x001F，随后延迟 125ms 让流水可见 */
    li.w      $s1, 0x1F
    st.w      $s1, $t7, 0
    li.w      $s5, 31250            /* 31250 轮 x 4us（2 指令 x 2us）= 125ms */
DELAY4:
    addi.w    $s5, $s5, -1
    bne       $s5, $zero, DELAY4

/* ===========================================================================
 * 组 5：乘除 mul.w / mulh.w / mulh.wu / div.w / div.wu / mod.w / mod.wu
 *   MDU 为多周期单元，本组同时验证握手时序
 * =========================================================================*/
    li.w      $s3, 5
    mul.w     $sp, $ra, $tp         /* 低 32 位：10 * 3 = 30 */
    li.w      $s4, 0
    li.w      $s2, 30
    bne       $s2, $sp, FAIL

    mulh.w    $sp, $ra, $tp         /* 高 32 位：10 * 3 -> 0 */
    li.w      $s4, 1
    li.w      $s2, 0
    bne       $s2, $sp, FAIL

    mulh.wu   $sp, $ra, $tp         /* 无符号高 32 位 -> 0 */
    li.w      $s4, 2
    li.w      $s2, 0
    bne       $s2, $sp, FAIL

    div.w     $sp, $ra, $tp         /* 10 / 3 = 3 */
    li.w      $s4, 3
    li.w      $s2, 3
    bne       $s2, $sp, FAIL

    div.wu    $sp, $ra, $tp         /* 无符号 10 / 3 = 3 */
    li.w      $s4, 4
    li.w      $s2, 3
    bne       $s2, $sp, FAIL

    mod.w     $sp, $ra, $tp         /* 10 % 3 = 1 */
    li.w      $s4, 5
    li.w      $s2, 1
    bne       $s2, $sp, FAIL

    mod.wu    $sp, $ra, $tp         /* 无符号 10 % 3 = 1 */
    li.w      $s4, 6
    li.w      $s2, 1
    bne       $s2, $sp, FAIL

    /* 进度灯：组 5 通过，LED = 0x003F，随后延迟 125ms 让流水可见 */
    li.w      $s1, 0x3F
    st.w      $s1, $t7, 0
    li.w      $s5, 31250            /* 31250 轮 x 4us（2 指令 x 2us）= 125ms */
DELAY5:
    addi.w    $s5, $s5, -1
    bne       $s5, $zero, DELAY5

/* ===========================================================================
 * 组 6：访存 st.w/ld.w/st.h/ld.h/ld.hu/st.b/ld.b/ld.bu（验证符号扩展）
 * =========================================================================*/
    li.w      $s3, 6
    lu12i.w   $s2, 0x12345
    ori       $s2, $s2, 0x678       /* $s2 = 0x12345678 */
    st.w      $s2, $t8, 0
    ld.w      $sp, $t8, 0
    li.w      $s4, 1
    bne       $s2, $sp, FAIL

    lu12i.w   $s2, 0x5              /* $s2 = 0x00050678 */
    ori       $s2, $s2, 0x678
    st.h      $s2, $t8, 4           /* 存半字 0x0678 */
    ld.h      $sp, $t8, 4           /* 读回并符号扩展 -> 0x00000678 */
    li.w      $s4, 3
    bne       $s2, $sp, FAIL

    ld.hu     $sp, $t8, 4           /* 读回零扩展 -> 0x00000678 */
    li.w      $s4, 4
    bne       $s2, $sp, FAIL

    li.w      $s2, -1
    st.b      $s2, $t8, 8           /* 存字节 0xFF */
    ld.b      $sp, $t8, 8           /* 符号扩展 -> 0xFFFFFFFF */
    li.w      $s4, 6
    li.w      $s2, -1
    bne       $s2, $sp, FAIL

    ld.bu     $sp, $t8, 8           /* 零扩展 -> 0x000000FF */
    li.w      $s4, 7
    li.w      $s2, 255
    bne       $s2, $sp, FAIL

    /* 进度灯：组 6 通过，LED = 0x007F，随后延迟 125ms 让流水可见 */
    li.w      $s1, 0x7F
    st.w      $s1, $t7, 0
    li.w      $s5, 31250            /* 31250 轮 x 4us（2 指令 x 2us）= 125ms */
DELAY6:
    addi.w    $s5, $s5, -1
    bne       $s5, $zero, DELAY6

/* ===========================================================================
 * 组 7：分支与跳转 beq / bne / blt / bge / bltu / bgeu / b / bl / jirl
 *   判据：条件成立则应跳过紧邻的 li.w $sp, 1，使 $sp 保持 0
 * =========================================================================*/
    li.w      $s3, 7

    li.w      $sp, 0
    beq       $ra, $ra, 1f          /* $ra == $ra 恒真 -> 跳过下一条 */
    li.w      $sp, 1
1:
    li.w      $s4, 0
    li.w      $s2, 0
    bne       $s2, $sp, FAIL

    li.w      $sp, 0
    bne       $ra, $tp, 2f          /* 10 != 3 为真 -> 跳过下一条 */
    li.w      $sp, 1
2:
    li.w      $s4, 1
    li.w      $s2, 0
    bne       $s2, $sp, FAIL

    li.w      $sp, 0
    blt       $tp, $ra, 3f          /* 3 < 10 为真 -> 跳过下一条 */
    li.w      $sp, 1
3:
    li.w      $s4, 2
    li.w      $s2, 0
    bne       $s2, $sp, FAIL

    li.w      $sp, 0
    bge       $ra, $tp, 4f          /* 10 >= 3 为真 -> 跳过下一条 */
    li.w      $sp, 1
4:
    li.w      $s4, 3
    li.w      $s2, 0
    bne       $s2, $sp, FAIL

    li.w      $sp, 0
    bltu      $tp, $ra, 5f          /* 3 < 10 无符号为真 -> 跳过下一条 */
    li.w      $sp, 1
5:
    li.w      $s4, 4
    li.w      $s2, 0
    bne       $s2, $sp, FAIL

    li.w      $sp, 0
    bgeu      $ra, $tp, 6f          /* 10 >= 3 无符号为真 -> 跳过下一条 */
    li.w      $sp, 1
6:
    li.w      $s4, 5
    li.w      $s2, 0
    bne       $s2, $sp, FAIL

    /* b：无条件跳过置位语句 */
    li.w      $sp, 0
    b         7f
    li.w      $sp, 1
7:
    li.w      $s4, 6
    li.w      $s2, 0
    bne       $s2, $sp, FAIL

    /* bl / jirl 配合：bl 跳到标签 9 并把返回地址写入 $ra；
       9 处设 $sp=1 后用 jirl 借 $ra 跳回标签 8，验证链接寄存器与间接跳转。
       注意证据值 $sp=1 是设在 bl 的「跳转目标」里，而非返回路径上 */
    li.w      $sp, 0
    bl        9f                    /* 跳到 9f，$ra <- 标签 8 的地址 */
8:
    li.w      $a0, 0                /* jirl 跳回此处执行，作为"确实跳回来了"的证据 */
    b         10f                   /* 跳过 9 段，避免顺序执行又落进 jirl */
9:
    li.w      $sp, 1                /* 在 bl 的跳转目标处设置证据值 */
    jirl      $a1, $ra, 0           /* 跳回 $ra（标签 8），同时把 PC+4 写入 $a1 */
10:
    li.w      $s4, 7
    li.w      $s2, 1
    bne       $s2, $sp, FAIL        /* 校验 $sp == 1，证明 bl 与 jirl 往返成功 */

    /* 进度灯：组 7 通过，LED = 0x00FF（16 位板上 8 灯亮，距全亮差 8 灯），
       随后延迟 125ms，再进入 PASS 全亮，总流水约 1s */
    li.w      $s1, 0xFF
    st.w      $s1, $t7, 0
    li.w      $s5, 31250            /* 31250 轮 x 4us（2 指令 x 2us）= 125ms */
DELAY7:
    addi.w    $s5, $s5, -1
    bne       $s5, $zero, DELAY7

/* ===========================================================================
 * 组 8：立即数扩展与有/无符号语义（区分零扩展与符号扩展、有符号与无符号比较）
 *   原有各组的操作数均为正数且立即数 bit11 为 0，无法区分下列易错语义
 * =========================================================================*/
    li.w      $s3, 8

    /* ori 零扩展：0x800 的 bit11 为 1，符号扩展会得到 0xFFFFF800 */
    ori       $sp, $zero, 0x800
    li.w      $s4, 0
    li.w      $s2, 0x800
    bne       $s2, $sp, FAIL

    /* sltui 立即数符号扩展：-1 扩展为 0xFFFFFFFF，$a0=0xFFF < 0xFFFFFFFF 为真 -> 1；
       若误做零扩展则为 0xFFF，0xFFF < 0xFFF 为假 -> 0 */
    li.w      $a0, 0xFFF
    sltui     $sp, $a0, -1
    li.w      $s4, 1
    li.w      $s2, 1
    bne       $s2, $sp, FAIL

    /* slt 有符号：-1 < 10 为真 -> 1；若误做无符号则 0xFFFFFFFF < 10 为假 */
    li.w      $a0, -1
    slt       $sp, $a0, $ra
    li.w      $s4, 2
    li.w      $s2, 1
    bne       $s2, $sp, FAIL

    /* sltu 无符号：0xFFFFFFFF < 10 为假 -> 0 */
    sltu      $sp, $a0, $ra
    li.w      $s4, 3
    li.w      $s2, 0
    bne       $s2, $sp, FAIL

    /* blt 有符号：-1 < 10 为真，必须跳转（跳过置位语句）；若误做无符号则不跳 */
    li.w      $sp, 0
    blt       $a0, $ra, 11f
    li.w      $sp, 1
11:
    li.w      $s4, 4
    li.w      $s2, 0
    bne       $s2, $sp, FAIL

    /* beq 不跳转路径：10 != 3，不应跳转；若误跳转则 $sp 保持 1 而非 0 */
    li.w      $sp, 0
    beq       $ra, $tp, 12f
    li.w      $sp, 1
12:
    li.w      $s4, 5
    li.w      $s2, 1
    bne       $s2, $sp, FAIL

    /* 进度灯：组 8 通过，LED = 0x01FF，随后延迟 125ms */
    li.w      $s1, 0x1FF
    st.w      $s1, $t7, 0
    li.w      $s5, 31250
DELAY8:
    addi.w    $s5, $s5, -1
    bne       $s5, $zero, DELAY8

/* ===========================================================================
 * 组 9：字节通道 1..3、LD.H 负数、MULH 负数、DIV/MOD 负数与边界
 * =========================================================================*/
    li.w      $s3, 9

    /* 小端字节布局：word 0x11223344 的字节 0=0x44 1=0x33 2=0x22 3=0x11 */
    lu12i.w   $s2, 0x11223          /* 0x11223000 */
    ori       $s2, $s2, 0x344       /* $s2 = 0x11223344 */
    st.w      $s2, $t8, 12
    ld.bu     $sp, $t8, 13          /* 字节通道 1 -> 0x33 */
    li.w      $s4, 0
    li.w      $s2, 0x33
    bne       $s2, $sp, FAIL

    ld.bu     $sp, $t8, 14          /* 字节通道 2 -> 0x22 */
    li.w      $s4, 1
    li.w      $s2, 0x22
    bne       $s2, $sp, FAIL

    ld.bu     $sp, $t8, 15          /* 字节通道 3 -> 0x11 */
    li.w      $s4, 2
    li.w      $s2, 0x11
    bne       $s2, $sp, FAIL

    /* ST.B 写非零通道：只改字节 1，其余字节保持 */
    li.w      $s2, 0xAB
    st.b      $s2, $t8, 13
    ld.w      $sp, $t8, 12          /* 期望 0x1122AB44 */
    li.w      $s4, 3
    lu12i.w   $s2, 0x1122A
    ori       $s2, $s2, 0xB44
    bne       $s2, $sp, FAIL

    /* LD.H 负半字：0x8001 符号扩展为 0xFFFF8001 */
    li.w      $s2, 0x8001
    st.h      $s2, $t8, 16
    ld.h      $sp, $t8, 16
    li.w      $s4, 4
    lu12i.w   $s2, -8               /* 20 位有符号立即数 -8 = 0xFFFF8，<<12 后为 0xFFFF8000 */
    ori       $s2, $s2, 0x001       /* $s2 = 0xFFFF8001 */
    bne       $s2, $sp, FAIL

    /* MULH.W 负数：-2 * 3 = -6，高 32 位为 0xFFFFFFFF */
    li.w      $a0, -2
    mulh.w    $sp, $a0, $tp
    li.w      $s4, 5
    li.w      $s2, -1
    bne       $s2, $sp, FAIL

    /* DIV.W / MOD.W 负数：-10 / 3 = -3（向零截断），-10 % 3 = -1（与被除数同号） */
    li.w      $a0, -10
    div.w     $sp, $a0, $tp
    li.w      $s4, 6
    li.w      $s2, -3
    bne       $s2, $sp, FAIL

    mod.w     $sp, $a0, $tp
    li.w      $s4, 7
    li.w      $s2, -1
    bne       $s2, $sp, FAIL

    /* 除 0 边界：商 = 0xFFFFFFFF，余数 = 被除数（与 mdu.v 文档一致） */
    div.w     $sp, $ra, $zero
    li.w      $s4, 8
    li.w      $s2, -1
    bne       $s2, $sp, FAIL

    /* -2^31 / -1 溢出边界：商固定 0x80000000，余数 0 */
    lu12i.w   $a0, -524288          /* 20 位有符号 -524288 = 0x80000，<<12 后为 0x80000000 */
    li.w      $a1, -1
    div.w     $sp, $a0, $a1
    li.w      $s4, 9
    lu12i.w   $s2, -524288          /* $s2 = 0x80000000 */
    bne       $s2, $sp, FAIL

    mod.w     $sp, $a0, $a1
    li.w      $s4, 10
    li.w      $s2, 0
    bne       $s2, $sp, FAIL

    /* 进度灯：组 9 通过，LED = 0x03FF */
    li.w      $s1, 0x3FF
    st.w      $s1, $t7, 0
    li.w      $s5, 31250
DELAY9:
    addi.w    $s5, $s5, -1
    bne       $s5, $zero, DELAY9

/* ===========================================================================
 * 全部通过：LED 全亮 + 数码管 88888888，然后原地停机
 * =========================================================================*/
PASS:
    li.w      $s1, -1
    st.w      $s1, $t7, 0           /* LED       <- 0xFFFFFFFF 全亮 */
    li.w      $s1, -1
    st.w      $s1, $t7, 12          /* seg_cs    <- 0xFFFFFFFF 全位选 */
    li.w      $s1, 127
    st.w      $s1, $t7, 4           /* seg_data0 <- 0x7F 显示 "8" */
    li.w      $s1, 127
    st.w      $s1, $t7, 8           /* seg_data1 <- 0x7F 显示 "8" */
HALT:
    b         HALT                  /* 原地停机 */

/* ===========================================================================
 * 失败：LED 显示「组号<<8 | 项号」（进度灯同时定格在已通过组数）；
 *   数码管位 0 显示组号数字（0..9）、位 4 显示项号数字（0..9），
 *   项号带小数点（DP 位），与组号区分。
 *   段码表在启动时写入 dmem 0x10000100，此处用 ld.w 查表。
 * =========================================================================*/
FAIL:
    slli.w    $s1, $s3, 8
    or        $s1, $s1, $s4
    st.w      $s1, $t7, 0           /* LED <- 错误码 */

    slli.w    $s2, $s3, 2           /* 组号*4 -> 段码表偏移 */
    add.w     $s1, $t6, $s2         /* $s1 = 段码表基址 + 组号*4 */
    ld.w      $s1, $s1, 0           /* $s1 = 组号段码 */
    st.w      $s1, $t7, 4           /* seg_data0 <- 组号数字 */
    li.w      $s1, 0x01
    st.w      $s1, $t7, 12          /* seg_cs    <- 0x01，点亮位 0 */

    slli.w    $s2, $s4, 2           /* 项号*4 -> 段码表偏移 */
    add.w     $s1, $t6, $s2
    ld.w      $s1, $s1, 0           /* $s1 = 项号段码 */
    ori       $s1, $s1, 0x80        /* 置 DP 位：项号带小数点，与组号区分 */
    st.w      $s1, $t7, 8           /* seg_data1 <- 项号数字 */
    li.w      $s1, 0x11
    st.w      $s1, $t7, 12          /* seg_cs    <- 0x11，点亮位 0 和位 4 */

    b         FAIL_HALT
FAIL_HALT:
    b         FAIL_HALT             /* 原地停机，等待复位 */
