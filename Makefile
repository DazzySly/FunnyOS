ASM     = nasm
QEMU    = qemu-system-i386

BUILD_DIR = build

STAGE1_SRC = src/boot/stage1.asm
STAGE2_SRC = src/boot/stage2.asm
KERNEL_SRC = src/kernel/kernel32.asm

STAGE1_BIN = $(BUILD_DIR)/stage1.bin
STAGE2_BIN = $(BUILD_DIR)/stage2.bin
KERNEL_BIN = $(BUILD_DIR)/kernel32.bin
IMG        = $(BUILD_DIR)/funnyos32.img

.PHONY: all run run-mute clean


all: $(IMG)


$(IMG): $(STAGE1_BIN) $(STAGE2_BIN) $(KERNEL_BIN)
	dd if=/dev/zero of=$@ bs=512 count=2880
	dd if=$(STAGE1_BIN) of=$@ conv=notrunc
	dd if=$(STAGE2_BIN) of=$@ bs=512 seek=1 conv=notrunc
	dd if=$(KERNEL_BIN) of=$@ bs=512 seek=3 conv=notrunc
	@echo "--- image ready: $@ ---"


$(STAGE1_BIN): $(STAGE1_SRC)
	@mkdir -p $(BUILD_DIR)
	$(ASM) $< -f bin -o $@


$(STAGE2_BIN): $(STAGE2_SRC)
	@mkdir -p $(BUILD_DIR)
	$(ASM) $< -f bin -o $@
	@SIZE=$$(stat -c%s $@); \
	if [ $$SIZE -gt 3584 ]; then \
	    echo "ОШИБКА: stage2 $$SIZE байт > 7 секторов"; \
	    exit 1; \
	fi


$(KERNEL_BIN): $(KERNEL_SRC)
	@mkdir -p $(BUILD_DIR)
	$(ASM) $< -f bin -o $@
	@SIZE=$$(stat -c%s $@); \
	if [ $$SIZE -gt 6656 ]; then \
	    echo "ОШИБКА: ядро $$SIZE байт > 13 секторов"; \
	    exit 1; \
	fi


run: $(IMG)
	$(QEMU) -drive file=$(IMG),format=raw,if=ide


run-mute: $(IMG)
	$(QEMU) -drive file=$(IMG),format=raw,if=ide


clean:
	rm -rf $(BUILD_DIR)
