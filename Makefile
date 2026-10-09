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

.PHONY: all floppy_image stage1 stage2 kernel run run-floppy run-hdd clean


all: floppy_image


floppy_image: $(FLOPPY_IMG)

$(FLOPPY_IMG): $(STAGE1_BIN) $(STAGE2_BIN) $(KERNEL_BIN) mkfs.myfs
	./mkfs.myfs $(STAGE1_BIN) $(STAGE2_BIN) $(KERNEL_BIN) $@
	@echo "--- image ready: $@ ---"
	
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
	if [ $$SIZE -gt 14336 ]; then \
	    echo "ОШИБКА: ядро $$SIZE байт, превышает 28 секторов (14336 байт)"; \
	    exit 1; \
	fi

run: $(FLOPPY_IMG)
	$(QEMU) -drive file=$(FLOPPY_IMG),format=raw,if=ide \
	        -audiodev pipewire,id=snd0 \
	        -machine pcspk-audiodev=snd0

run-mute: $(FLOPPY_IMG)
	$(QEMU) -drive file=$(FLOPPY_IMG),format=raw,if=ide

run-hdd: run

clean:
	rm -rf $(BUILD_DIR)
