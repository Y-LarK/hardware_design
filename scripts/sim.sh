#!/usr/bin/env bash
# ============================================================================
# sim.sh —— 批处理行为仿真，只输出 PASS / FAIL 结论（Linux 用）
# ----------------------------------------------------------------------------
# 用法：
#   ./scripts/sim.sh                       仿真 pipeline（默认）
#   ./scripts/sim.sh single                仿真单周期基线
#   ./scripts/sim.sh single tests/hex/test_all.hex   指定 hex
#
# 退出码：0 = PASS，1 = FAIL，2 = UNKNOWN 或工具/编译错误
#
# 编译产物与 xsim 日志放在 out/sim/<design>/，不污染仓库根目录。
# 图形化波形请用 Vivado GUI 打开对应工程（见 create_project.tcl）。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VALID_DESIGNS="pipeline single"

# ---- 解析参数：位置1 = 设计名，位置2 = hex ----
DESIGN="pipeline"
HEX_ARG=""
for arg in "$@"; do
    if printf '%s\n' $VALID_DESIGNS | grep -qx "$arg"; then
        DESIGN="$arg"
    elif [ -z "$HEX_ARG" ] && { [ -f "$arg" ] || case "$arg" in *.hex|*.mem) true ;; *) false ;; esac; }; then
        # 只有「文件确实存在」或「看起来是 hex 路径」才当程序文件，
        # 否则拼错的参数会被误当成 hex，报出「程序文件不存在」这种误导性错误。
        HEX_ARG="$arg"
    else
        echo "ERROR: 无法识别的参数 '$arg'" >&2
        echo "       用法：$0 [pipeline|single] [hex 文件]" >&2
        exit 2
    fi
done

# ---- 设计 -> 目录/顶层映射（与 create_project.tcl、build.tcl 同构）----
case "$DESIGN" in
    single)
        RTL_DIR="$ROOT/archive/single_cycle/rtl"
        SIM_DIR="$ROOT/archive/single_cycle/sim"
        TOP_TB="tb_all"
        ;;
    pipeline)
        RTL_DIR="$ROOT/rtl"
        SIM_DIR="$ROOT/sim"
        TOP_TB="tb_pipeline"
        ;;
    *)
        echo "ERROR: 未知设计名 '$DESIGN'，可用值：$VALID_DESIGNS" >&2
        exit 2
        ;;
esac

HEX="${HEX_ARG:-$ROOT/tests/hex/test_all.hex}"
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

# 该设计的 RTL / TB 是否就位（流水线尚未开工时给出明确信息）
if ! compgen -G "$RTL_DIR/*.v" >/dev/null; then
    echo "ERROR: 设计 '$DESIGN' 的 RTL 目录为空：$RTL_DIR" >&2
    [ "$DESIGN" = "pipeline" ] && echo "       流水线版本尚未开始，先把 RTL 放进 rtl/ 再来。" >&2
    exit 2
fi
if ! compgen -G "$SIM_DIR/*.v" >/dev/null; then
    echo "ERROR: 设计 '$DESIGN' 的 sim 目录为空：$SIM_DIR" >&2
    exit 2
fi

OUT_DIR="$ROOT/out/sim/$DESIGN"
mkdir -p "$OUT_DIR"
LOG="$OUT_DIR/xsim.log"

# ---- 编译 / 展开 / 运行（IMEM_FILE 用绝对路径，与运行目录无关）----
cd "$OUT_DIR"
"$XSIM_BIN/xvlog" -d "IMEM_FILE=\"$HEX\"" \
    "$RTL_DIR"/*.v "$SIM_DIR"/*.v > xvlog.log 2>&1 \
    || { echo "ERROR: xvlog 编译失败，见 $OUT_DIR/xvlog.log" >&2; exit 2; }
"$XSIM_BIN/xelab" -debug off "$TOP_TB" -s tb_sim > xelab.log 2>&1 \
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
