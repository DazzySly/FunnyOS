org 0x7C00
bits 16


%define ENDL 0x0D, 0x0A

%define STAGE2_LBA      1
%define STAGE2_SECTORS  7
%define STAGE2_SEG      0x0000
%define STAGE2_OFF      0x7E00

jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 16
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880
bdb_media_descriptor_type:  db 0F0h
bdb_sectors_per_fat:        dw 9
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

ebr_drive_number:           db 0
                            db 0
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h
ebr_volume_label:           db 'NANOBYTE OS'
ebr_system_id:              db 'FAT12   '


start:
    jmp main


;
; выводит строку на экран
; параметры:
;   - ds:si указывает на строку
;
puts:
    push si
    push ax
    push bx

.loop:
    lodsb
    or al, al
    jz .done

    mov ah, 0x0E
    mov bh, 0
    int 0x10

    jmp .loop

.done:
    pop bx
    pop ax
    pop si
    ret


main:
    mov ax, 0
    mov ds, ax
    mov es, ax

    mov ss, ax
    mov sp, 0x7C00

    ; BIOS передал номер загрузочного диска в DL
    mov [ebr_drive_number], dl

    mov si, msg_stage1
    call puts

    ; читаем stage2 с диска
    mov ax, STAGE2_LBA
    mov cx, STAGE2_SECTORS
    push word STAGE2_SEG
    pop es
    mov bx, STAGE2_OFF
    call disk_read_multi

    mov si, msg_jump
    call puts

    mov dl, [ebr_drive_number]
    jmp STAGE2_SEG:STAGE2_OFF


;
; читает N секторов, начиная с LBA в ax
; параметры:
;   - ax: адрес LBA
;   - cx: количество секторов
;   - es:bx: адрес в памяти, куда сохранить прочитанные данные
;
disk_read_multi:
    push ax
    push bx
    push cx
    push dx

.loop:
    push ax
    push bx
    push cx

    mov cx, 1
    call disk_read

    pop cx
    pop bx
    pop ax

    add bx, 512
    inc ax
    loop .loop

    pop dx
    pop cx
    pop bx
    pop ax
    ret


;
; читает один сектор через int 13h ah=42h (LBA Extended Read)
; параметры:
;   - ax: адрес LBA
;   - es:bx: адрес в памяти, куда сохранить прочитанные данные
;
disk_read:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds

    ; сохраняем буфер
    mov di, bx              ; DI = смещение буфера
    mov cx, es              ; CX = сегмент буфера

    ; резервируем 16 байт под DAP
    sub sp, 16
    mov bp, sp

    mov byte [bp + 0], 0x10     ; размер DAP
    mov byte [bp + 1], 0        ; зарезервировано
    mov word [bp + 2], 1        ; количество секторов
    mov word [bp + 4], di       ; смещение буфера
    mov word [bp + 6], cx       ; сегмент буфера
    mov word [bp + 8], ax       ; LBA младшее слово
    mov word [bp + 10], 0
    mov word [bp + 12], 0
    mov word [bp + 14], 0

    mov si, bp                  ; SI = указатель на DAP
    mov dl, [ebr_drive_number]
    mov ah, 0x42
    stc
    int 13h
    jc .fail

    add sp, 16

    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

.fail:
    add sp, 16
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    jmp floppy_error


;
; сбрасывает контроллер диска
;
disk_reset:
    pusha
    mov ah, 0
    stc
    int 13h
    jc floppy_error
    popa
    ret


;
; обработчики ошибок
;

floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0
    int 16h
    jmp 0FFFFh:0

.halt:
    cli
    hlt


msg_stage1:      db 'Stage1: loading...', ENDL, 0
msg_jump:        db 'Stage1: jumping to stage2', ENDL, 0
msg_read_failed: db 'Stage1: read failed!', ENDL, 0

times 510-($-$$) db 0
dw 0AA55h
