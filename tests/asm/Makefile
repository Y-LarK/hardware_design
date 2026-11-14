# ============================================================================
# Makefile —— LA32R 测试程序汇编/反汇编
# ----------------------------------------------------------------------------
# 用法：
#   make                    汇编 -> ELF -> 纯二进制 -> ../hex/test_all.hex
#   make DESIGN=pipeline    同上，但按流水线主频选延时轮数
#   make disasm             反汇编 ELF（核对机器码）
#   make hexdump            查看生成的 hex
#   make clean              清理中间产物
#
# 依赖：loongarch64-linux-gnu-binutils（Fedora 包 binutils-loongarch64-linux-gnu）
#   sudo dnf5 install -y binutils-loongarch64-linux-gnu
#
# 【DESIGN 的作用】
#   两套设计共用这一份汇编源与同一个 hex 输出，唯一随设计变的是进度灯的
#   延时轮数（LED 流水要肉眼可见，轮数取决于 CPU 主频）：
#     single   : CPU 0.5 MHz（CLK_DIV=100）-> 31250 轮 ≈ 125ms
#     pipeline : 目标 100 MHz             -> 需放大约 6250 倍
#   注意 GNU as 的 -D 是「输出调试信息」，定义符号必须用 --defsym。
#   两套设计不会同时上板，所以 hex 保持单一文件名，避免「哪份 hex 生效」的新坑。
#   要临时换设计：make clean && make DESIGN=pipeline
# ============================================================================

AS      := loongarch64-linux-gnu-as
OBJCOPY := loongarch64-linux-gnu-objcopy
OBJDUMP := loongarch64-linux-gnu-objdump

DESIGN ?= single

SRC := test_all.s
ELF := test_all.elf
BIN := test_all.bin
HEX := ../hex/test_all.hex

# 设计 -> 延时轮数
ifeq ($(DESIGN),single)
DELAY_COUNT := 31250
else ifeq ($(DESIGN),pipeline)
DELAY_COUNT := 195312500
else
$(error 未知 DESIGN='$(DESIGN)'，可用值：single / pipeline)
endif

ASFLAGS := --defsym DELAY_COUNT=$(DELAY_COUNT)

# 上次用的 DESIGN 记到文件里：换设计时立即数变了但 .s 时间戳没变，
# 只靠 $(ELF): $(SRC) 的依赖判断不会重编，会静默沿用旧意象。
# 用 stamp 文件把 DESIGN 纳入依赖，改设计必然触发重编。
STAMP := .design-stamp

.PHONY: all disasm hexdump clean

all: $(HEX)

$(STAMP): FORCE
	@echo '$(DESIGN)' | cmp -s - $@ || echo '$(DESIGN)' > $@
FORCE:

$(ELF): $(SRC) $(STAMP)
	$(AS) $(ASFLAGS) -o $@ $<

# 抽成纯二进制（无 ELF 头），作为 $readmemh 的数据源
$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

# 转成 $readmemh 可读的十六进制文本：每行一个 32 位字
#   od -tx4 在 x86 上按小端解释 4 字节，正好还原出指令字面值
$(HEX): $(BIN)
	od -An -tx4 -v -w4 $< | tr -d ' ' > $@
	@echo "生成 $@ ：$$(wc -l < $@) 条指令（DESIGN=$(DESIGN)，DELAY_COUNT=$(DELAY_COUNT)）"

disasm: $(ELF)
	$(OBJDUMP) -d -M no-aliases $<

hexdump: $(HEX)
	cat $(HEX)

clean:
	rm -f $(ELF) $(BIN) $(STAMP)
