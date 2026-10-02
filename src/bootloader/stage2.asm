org 0x7E00
bits 16


%define ENDL 0x0D, 0x0A

;
; константы FAT12 для образа с -R 16
;
%define FAT_START_LBA        16
%define ROOT_DIR_START_LBA   34
%define ROOT_DIR_SECTORS     14
%define DATA_START_LBA       48

;
; карта памяти
;   0x1000 – 0x7BFF : ядро
;   0x7C00 – 0x7DFF : stage1
;   0x7E00 – 0x8BFF : stage2
;
%define KERNEL_LBA       8
%define KERNEL_SECTORS   8
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

    mov [ebr_drive_number], dl

    mov si, msg_stage2
    call puts

    ; читаем ядро напрямую с диска
    push es
    mov cx, KERNEL_LOAD_SEG
    mov es, cx
    mov bx, KERNEL_LOAD_OFF

    mov ax, KERNEL_LBA
    mov cx, KERNEL_SECTORS
    call disk_read_multi

    pop es

    mov si, msg_jumping
    call puts

    mov dl, [ebr_drive_number]
    jmp KERNEL_LOAD_SEG:KERNEL_LOAD_OFF


;
; читает N секторов, начиная с LBA в ax
; параметры:
;   - ax: адрес LBA
;   - cx: количество секторов
;   - bx: адрес в памяти, куда сохранить прочитанные данные
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

    mov cl, 1
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
; преобразует адрес LBA в адрес CHS
; параметры:
;   - ax: адрес LBA
; возвращает:
;   - cx [биты 0-5]: номер сектора
;   - cx [биты 6-15]: цилиндр
;   - dh: головка
;
lba_to_chs:
    push ax

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

    pop ax
    ret


;
; читает один сектор с диска через int 13h ah=02h
; параметры:
;   - ax: адрес LBA
;   - es:bx: адрес в памяти, куда сохранить прочитанные данные
;
disk_read:
    push ax
    push bx
    push cx
    push dx
    push di

    mov di, bx              ; DI = смещение буфера

    call lba_to_chs         ; CX = CHS, DH = головка

    mov dl, [ebr_drive_number]
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

.fail:
    jmp floppy_error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret


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

sectors_per_track:  dw 18
heads:              dw 2
ebr_drive_number:   db 0

msg_stage2:         db 'Stage2: started', ENDL, 0
msg_jumping:        db 'Stage2: jumping to kernel', ENDL, 0
msg_read_failed:    db 'Stage2: read failed!', ENDL, 0
