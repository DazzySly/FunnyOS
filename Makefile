ASM     = nasm
QEMU    = qemu-system-i386

SRC_DIR   = src
BUILD_DIR = build

STAGE1_SRC = $(SRC_DIR)/bootloader/stage1.asm
STAGE2_SRC = $(SRC_DIR)/bootloader/stage2.asm
KERNEL_SRC = $(SRC_DIR)/kernel/main.asm

STAGE1_BIN = $(BUILD_DIR)/stage1.bin
STAGE2_BIN = $(BUILD_DIR)/stage2.bin
KERNEL_BIN = $(BUILD_DIR)/KERNEL.BIN
FLOPPY_IMG = $(BUILD_DIR)/main_floppy.img

.PHONY: all floppy_image stage1 stage2 kernel run clean


all: floppy_image


floppy_image: $(FLOPPY_IMG)

$(FLOPPY_IMG): $(STAGE1_BIN) $(STAGE2_BIN) $(KERNEL_BIN)
	dd if=/dev/zero of=$@ bs=512 count=2880
	mkfs.fat -F 12 -R 16 -n "NBOS" $@
	dd if=$(STAGE1_BIN) of=$@ conv=notrunc
	dd if=$(STAGE2_BIN) of=$@ bs=512 seek=1 conv=notrunc
	dd if=$(KERNEL_BIN) of=$@ bs=512 seek=8 conv=notrunc
	@echo "--- содержимое образа ---"
	@mdir -i $@ ::
	@echo "-------------------------"


stage1: $(STAGE1_BIN)

$(STAGE1_BIN): $(STAGE1_SRC)
	@mkdir -p $(BUILD_DIR)
	$(ASM) $< -f bin -o $@


stage2: $(STAGE2_BIN)

$(STAGE2_BIN): $(STAGE2_SRC)
	@mkdir -p $(BUILD_DIR)
	$(ASM) $< -f bin -o $@


kernel: $(KERNEL_BIN)

$(KERNEL_BIN): $(KERNEL_SRC)
	@mkdir -p $(BUILD_DIR)
	$(ASM) $< -f bin -o $@
	@SIZE=$$(stat -c%s $@); \
	if [ $$SIZE -gt 8192 ]; then \
	    echo "ОШИБКА: ядро $$SIZE байт, превышает 16 секторов (8192 байт)"; \
	    exit 1; \
	fi

run: $(FLOPPY_IMG)
	$(QEMU) -fda $(FLOPPY_IMG)


clean:
	rm -rf $(BUILD_DIR)
