org 0x7E00
bits 16


%define ENDL 0x0D, 0x0A
%define KERNEL_LBA       8
%define KERNEL_SECTORS   16
%define KERNEL_LOAD_SEG  0x0000
%define KERNEL_LOAD_OFF  0x1000


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

    ; BIOS передал номер диска в DL — сохраняем
    mov [ebr_drive_number], dl

    mov si, msg_stage2
    call puts

    ; читаем ядро с диска
    push word KERNEL_LOAD_SEG
    pop es
    mov bx, KERNEL_LOAD_OFF

    mov ax, KERNEL_LBA
    mov cx, KERNEL_SECTORS
    call disk_read_multi

    mov si, msg_jumping
    call puts

    mov dl, [ebr_drive_number]
    jmp KERNEL_LOAD_SEG:KERNEL_LOAD_OFF


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

    mov di, bx              ; DI = смещение буфера
    mov cx, es              ; CX = сегмент буфера

    sub sp, 16
    mov bp, sp

    mov byte [bp + 0], 0x10
    mov byte [bp + 1], 0
    mov word [bp + 2], 1
    mov word [bp + 4], di
    mov word [bp + 6], cx
    mov word [bp + 8], ax
    mov word [bp + 10], 0
    mov word [bp + 12], 0
    mov word [bp + 14], 0

    mov si, bp
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


;
; данные
;

ebr_drive_number:   db 0

msg_stage2:         db 'Stage2: started', ENDL, 0
msg_jumping:        db 'Stage2: jumping to kernel', ENDL, 0
msg_read_failed:    db 'Stage2: read failed!', ENDL, 0
