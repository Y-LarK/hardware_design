#!/usr/bin/env bash
# ============================================================================
# build.sh —— 一键构建（综合 -> 实现 -> 比特流），Linux 用
# ----------------------------------------------------------------------------
# 用法：
#   ./scripts/build.sh                    构建 pipeline（默认）
#   ./scripts/build.sh single             构建单周期基线
#   ./scripts/build.sh single program     构建单周期并烧录
#   ./scripts/build.sh pipeline           构建流水线
#
# 参数：第一个是设计名（pipeline / single），第二个出现 program 即烧录。
# 为兼容旧习惯，`./scripts/build.sh program` 也识别为「构建默认设计并烧录」。
#
# 队友（Windows）请用同目录的 build.bat
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VALID_DESIGNS="pipeline single"

# ---- 解析参数：位置1 = 设计名（可省略），出现 program 即烧录 ----
DESIGN="pipeline"
DO_PROGRAM=0
for arg in "$@"; do
    case "$arg" in
        program) DO_PROGRAM=1 ;;
        *)
            if printf '%s\n' $VALID_DESIGNS | grep -qx "$arg"; then
                DESIGN="$arg"
            else
                echo "ERROR: 未知参数 '$arg'，可用设计名：$VALID_DESIGNS；可选动作：program" >&2
                exit 1
            fi
            ;;
    esac
done

# ---- 定位 vivado（按优先级尝试）----
VIVADO=""
# 先查 PATH（用 command -v 解析成绝对路径，否则下面的 -x 判定会失败）
VIVADO="$(command -v vivado 2>/dev/null || true)"
# 再扫常见安装位置
if [ -z "$VIVADO" ]; then
    for p in "$HOME/Software/Xilinx/Vivado"/*/bin/vivado \
             /opt/Xilinx/Vivado/*/bin/vivado \
             /tools/Xilinx/Vivado/*/bin/vivado; do
        if [ -x "$p" ]; then VIVADO="$p"; break; fi
    done
fi

if [ -z "$VIVADO" ] || [ ! -x "$VIVADO" ]; then
    echo "ERROR: 找不到 vivado，请把它加入 PATH 或修改本脚本" >&2
    exit 1
fi

echo "使用 Vivado: $VIVADO"
echo "目标设计   : $DESIGN"

# ---- 1. 先汇编测试程序（若汇编源比 hex 新）----
# DESIGN 透传给 Makefile，用来选延时轮数（单周期 0.5 MHz，流水线 100 MHz）
if [ -f "$ROOT/tests/asm/Makefile" ]; then
    echo ">>> 汇编测试程序（DESIGN=$DESIGN）"
    make -C "$ROOT/tests/asm" DESIGN="$DESIGN"
fi

# ---- 2. 构建 ----
echo ">>> 综合 + 实现 + 生成比特流"
mkdir -p "$ROOT/out"
"$VIVADO" -mode batch -source "$SCRIPT_DIR/build.tcl" -tclargs "$DESIGN" \
    -log "$ROOT/out/vivado_build.log" -journal "$ROOT/out/vivado_build.jou"

# ---- 3. 可选：烧录 ----
if [ "$DO_PROGRAM" = "1" ]; then
    echo ">>> 烧录到开发板"
    "$VIVADO" -mode batch -source "$SCRIPT_DIR/program.tcl" -tclargs "$DESIGN" \
        -log "$ROOT/out/vivado_program.log" -journal "$ROOT/out/vivado_program.jou"
fi

echo "完成。产物在 out/$DESIGN/"
