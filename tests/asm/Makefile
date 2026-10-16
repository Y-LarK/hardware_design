# ============================================================================
# Makefile —— LA32R 测试程序汇编/反汇编
# ----------------------------------------------------------------------------
# 用法：
#   make              汇编 -> ELF -> 纯二进制 -> ../hex/test_all.hex
#   make disasm       反汇编 ELF（核对机器码）
#   make hexdump      查看生成的 hex
#   make clean        清理中间产物
#
# 依赖：loongarch64-linux-gnu-binutils（Fedora 包 binutils-loongarch64-linux-gnu）
#   sudo dnf5 install -y binutils-loongarch64-linux-gnu
# ============================================================================

AS      := loongarch64-linux-gnu-as
OBJCOPY := loongarch64-linux-gnu-objcopy
OBJDUMP := loongarch64-linux-gnu-objdump

SRC := test_all.s
ELF := test_all.elf
BIN := test_all.bin
HEX := ../hex/test_all.hex

.PHONY: all disasm hexdump clean

all: $(HEX)

$(ELF): $(SRC)
	$(AS) -o $@ $<

# 抽成纯二进制（无 ELF 头），作为 $readmemh 的数据源
$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

# 转成 $readmemh 可读的十六进制文本：每行一个 32 位字
#   od -tx4 在 x86 上按小端解释 4 字节，正好还原出指令字面值
$(HEX): $(BIN)
	od -An -tx4 -v -w4 $< | tr -d ' ' > $@
	@echo "生成 $@ ：$$(wc -l < $@) 条指令"

disasm: $(ELF)
	$(OBJDUMP) -d -M no-aliases $<

hexdump: $(HEX)
	cat $(HEX)

clean:
	rm -f $(ELF) $(BIN)
