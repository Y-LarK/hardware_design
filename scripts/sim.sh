#!/usr/bin/env bash
# ============================================================================
# sim.sh —— 批处理行为仿真，只输出 PASS / FAIL 结论（Linux 用）
# ----------------------------------------------------------------------------
# 用法：
#   ./scripts/sim.sh [hex 文件]     默认 tests/hex/test_all.hex
#
# 退出码：0 = PASS，1 = FAIL，2 = UNKNOWN 或工具/编译错误
#
# 编译产物与 xsim 日志放在 out/sim/，不污染仓库根目录。
# 图形化波形请用 Vivado GUI 打开 cpu_single 工程（见 create_project.tcl）。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

HEX="${1:-$ROOT/tests/hex/test_all.hex}"
HEX="$(cd "$(dirname "$HEX")" && pwd)/$(basename "$HEX")"

# ---- 定位 xvlog / xelab / xsim（与 build.sh 同样的查找顺序）----
XSIM_BIN=""
XVLOG="$(command -v xvlog 2>/dev/null || true)"
if [ -n "$XVLOG" ]; then
    XSIM_BIN="$(dirname "$XVLOG")"
else
    for p in "$HOME/Software/Xilinx/Vivado"/*/bin/xvlog \
             /opt/Xilinx/Vivado/*/bin/xvlog \
             /tools/Xilinx/Vivado/*/bin/xvlog; do
        if [ -x "$p" ]; then XSIM_BIN="$(dirname "$p")"; break; fi
    done
fi

if [ -z "$XSIM_BIN" ]; then
    echo "ERROR: 找不到 xvlog，请把 Vivado 的 bin 目录加入 PATH" >&2
    exit 2
fi

if [ ! -f "$HEX" ]; then
    echo "ERROR: 程序文件不存在：$HEX" >&2
    exit 2
fi

OUT_DIR="$ROOT/out/sim"
mkdir -p "$OUT_DIR"
LOG="$OUT_DIR/xsim.log"

# ---- 编译 / 展开 / 运行（IMEM_FILE 用绝对路径，与运行目录无关）----
cd "$OUT_DIR"
"$XSIM_BIN/xvlog" -d "IMEM_FILE=\"$HEX\"" \
    "$ROOT"/rtl_single_cycle/*.v "$ROOT"/sim/tb_all.v > xvlog.log 2>&1 \
    || { echo "ERROR: xvlog 编译失败，见 $OUT_DIR/xvlog.log" >&2; exit 2; }
"$XSIM_BIN/xelab" -debug off tb_all -s tb_sim > xelab.log 2>&1 \
    || { echo "ERROR: xelab 展开失败，见 $OUT_DIR/xelab.log" >&2; exit 2; }
"$XSIM_BIN/xsim" tb_sim -runall > "$LOG" 2>&1 \
    || { echo "ERROR: xsim 运行失败，见 $LOG" >&2; exit 2; }

RESULT_LINE="$(grep -E '== RESULT:' "$LOG" || true)"
if [ -z "$RESULT_LINE" ]; then
    echo "UNKNOWN：日志中没有 RESULT 行，见 $LOG" >&2
    exit 2
fi

echo "$RESULT_LINE"
case "$RESULT_LINE" in
    *"RESULT: PASS"*)    exit 0 ;;
    *"RESULT: FAIL"*)    exit 1 ;;
    *)                   exit 2 ;;
esac
