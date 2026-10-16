#!/usr/bin/env bash
# ============================================================================
# build.sh —— 一键构建（综合 -> 实现 -> 比特流），Linux 用
# ----------------------------------------------------------------------------
# 用法：
#   ./scripts/build.sh          构建
#   ./scripts/build.sh program  构建并烧录到开发板
#
# 队友（Windows）请用同目录的 build.bat
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

# ---- 1. 先汇编测试程序（若汇编源比 hex 新）----
if [ -f "$ROOT/tests/asm/Makefile" ]; then
    echo ">>> 汇编测试程序"
    make -C "$ROOT/tests/asm"
fi

# ---- 2. 构建 ----
echo ">>> 综合 + 实现 + 生成比特流"
"$VIVADO" -mode batch -source "$SCRIPT_DIR/build.tcl" \
    -log "$ROOT/out/vivado_build.log" -journal "$ROOT/out/vivado_build.jou"

# ---- 3. 可选：烧录 ----
if [ "${1:-}" = "program" ]; then
    echo ">>> 烧录到开发板"
    "$VIVADO" -mode batch -source "$SCRIPT_DIR/program.tcl" \
        -log "$ROOT/out/vivado_program.log" -journal "$ROOT/out/vivado_program.jou"
fi

echo "完成。"
