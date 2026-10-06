org 0x7E00
bits 16

%define ENDL 0x0D, 0x0A
%define KERNEL_LBA      3
%define KERNEL_SECTORS  32
%define KERNEL_ADDR     0x1000

start:
    jmp main

puts16:
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

    mov [disk_num], dl

    mov si, msg_stage2
    call puts16

    ; ---- загружаем ядро с LBA 3 ----
    push word 0
    pop es
    mov bx, KERNEL_ADDR

    mov ax, KERNEL_LBA
    mov cx, KERNEL_SECTORS
    call disk_read_multi
    jc .read_fail

    mov si, msg_loaded
    call puts16

    ; ---- отключаем прерывания ----
    cli

    ; ---- загружаем GDT ----
    mov si, msg_gdt
    call puts16
    lgdt [gdt_descriptor]

    ; ---- включаем A20 ----
    mov si, msg_a20
    call puts16
    in al, 0x92
    or al, 2
    out 0x92, al

    ; ---- устанавливаем CR0.PE ----
    mov si, msg_pm
    call puts16
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; ---- far jump в 32-бит ядро ----
    jmp 0x08:pm_entry

.read_fail:
    mov si, msg_read_fail
    call puts16
.halt:
    cli
    hlt
    jmp .halt

;
; disk_read_multi / disk_read / lba_to_chs — те же, что в stage1
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
    call disk_read
    jc .fail
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
    clc
    ret
.fail:
    pop cx
    pop bx
    pop ax
    pop dx
    pop cx
    pop bx
    pop ax
    stc
    ret

disk_read:
    push ax
    push bx
    push cx
    push dx
    push di
    mov di, bx
    call lba_to_chs
    mov dl, [disk_num]
    mov al, 1
    mov ah, 0x02
    mov bx, di
    mov di, 3
.retry:
    pusha
    stc
    int 13h
    jnc .done
    popa
    call disk_reset
    dec di
    test di, di
    jnz .retry
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    stc
    ret
.done:
    popa
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    clc
    ret

lba_to_chs:
    push ax
    push dx
    xor dx, dx
    div word [sectors_per_track]
    inc dx
    mov cx, dx
    xor dx, dx
    div word [heads]
    mov dh, dl
    mov ch, al
    shl ah, 6
    or cl, ah
    pop dx
    pop ax
    ret

disk_reset:
    pusha
    mov ah, 0
    stc
    int 13h
    popa
    ret

;
; =============== 32-битный код ===============
;
bits 32

pm_entry:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    mov esp, 0x90000

    ; ---- переход в ядро (0x1000) ----
    jmp 0x1000

;
; =============== GDT ===============
;
bits 16

gdt_start:
    dd 0x0
    dd 0x0

    ; code segment
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10011010b
    db 11001111b
    db 0x00

    ; data segment
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b
    db 11001111b
    db 0x00
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

;
; данные
;
disk_num:           db 0
sectors_per_track:  dw 18
heads:              dw 2

msg_stage2:      db 'Stage2: loading kernel...', ENDL, 0
msg_loaded:      db 'Stage2: kernel loaded', ENDL, 0
msg_gdt:         db 'Stage2: loading GDT', ENDL, 0
msg_a20:         db 'Stage2: enabling A20', ENDL, 0
msg_pm:          db 'Stage2: entering protected mode', ENDL, 0
msg_read_fail:   db 'Stage2: read failed!', ENDL, 0
