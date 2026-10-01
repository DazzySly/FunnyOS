ASM     = nasm
QEMU    = qemu-system-i386

SRC_DIR   = src
BUILD_DIR = build

BOOTLOADER_SRC = $(SRC_DIR)/bootloader/boot.asm
KERNEL_SRC     = $(SRC_DIR)/kernel/main.asm

BOOTLOADER_BIN = $(BUILD_DIR)/bootloader.bin
KERNEL_BIN     = $(BUILD_DIR)/kernel.bin
FLOPPY_IMG     = $(BUILD_DIR)/main_floppy.img

.PHONY: all floppy_image bootloader kernel run clean

#
; сборка всего
;
all: floppy_image

#
; образ флоппи
;
floppy_image: $(FLOPPY_IMG)

$(FLOPPY_IMG): $(BOOTLOADER_BIN) $(KERNEL_BIN)
	dd if=/dev/zero of=$@ bs=512 count=2880
	mkfs.fat -F 12 -n "NBOS" $@
	dd if=$(BOOTLOADER_BIN) of=$@ conv=notrunc
	mcopy -i $@ $(KERNEL_BIN) "::kernel.bin"


#
; загрузчик
;
bootloader: $(BOOTLOADER_BIN)

$(BOOTLOADER_BIN): $(BOOTLOADER_SRC)
	@mkdir -p $(BUILD_DIR)
	$(ASM) $< -f bin -o $@


#
; ядро
;
kernel: $(KERNEL_BIN)

$(KERNEL_BIN): $(KERNEL_SRC)
	@mkdir -p $(BUILD_DIR)
	$(ASM) $< -f bin -o $@


#
; запуск в qemu
;
run: $(FLOPPY_IMG)
	$(QEMU) -fda $(FLOPPY_IMG)


#
; очистка
;
clean:
	rm -rf $(BUILD_DIR)ASM=nasm

SRC_DIR=src
BUILD_DIR=build

.PHONY: all floppy_image kernel bootloader clean always

#
# Образ флоппи
#
floppy_image: $(BUILD_DIR)/main_floppy.img

$(BUILD_DIR)/main_floppy.img: bootloader kernel
	dd if=/dev/zero of=$(BUILD_DIR)/main_floppy.img bs=512 count=2880
	mkfs.fat -F 12 -n "NBOS" $(BUILD_DIR)/main_floppy.img
	dd if=$(BUILD_DIR)/bootloader.bin of=$(BUILD_DIR)/main_floppy.img conv=notrunc
	mcopy -i $(BUILD_DIR)/main_floppy.img $(BUILD_DIR)/kernel.bin "::kernel.bin"

#
# загрузчик
#
bootloader: $(BUILD_DIR)/bootloader.bin

$(BUILD_DIR)/bootloader.bin: always
	$(ASM) $(SRC_DIR)/bootloader/boot.asm -f bin -o $(BUILD_DIR)/bootloader.bin

#
# ядро
#
kernel: $(BUILD_DIR)/kernel.bin

$(BUILD_DIR)/kernel.bin: always
	$(ASM) $(SRC_DIR)/kernel/main.asm -f bin -o $(BUILD_DIR)/kernel.bin

always:
	mkdir -p $(BUILD_DIR)

#
# очистка
#
clean:
	rm -rf $(BUILD_DIR)/*
