org 0x7C00
bits 16


%define ENDL 0x0D, 0x0A

;
; константы FAT12 для образа 1.44 МБ, созданного mkfs.fat -F 12
;
%define FAT_START_LBA        1
%define ROOT_DIR_START_LBA   19
%define ROOT_DIR_SECTORS     14
%define DATA_START_LBA       33
%define SECTORS_PER_CLUSTER  1
%define KERNEL_LOAD_SEG      0x0000
%define KERNEL_LOAD_OFF      0x1000


;
; заголовок FAT12
;
jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
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

    mov [ebr_drive_number], dl

    mov si, msg_loading
    call puts

    ; читаем корневую директорию в 0x7E00
    mov ax, ROOT_DIR_START_LBA
    mov cx, ROOT_DIR_SECTORS
    mov bx, 0x7E00
    call disk_read_multi

    ; ищем KERNEL.BIN в директории
    mov di, 0x7E00
    mov cx, 224
.find_kernel:
    cmp byte [di], 0
    je .not_found
    cmp byte [di], 0xE5
    je .next
    cmp byte [di + 11], 0x0F
    je .next

    push cx
    push di
    mov si, kernel_name
    call fat_name_cmp
    pop di
    pop cx
    jc .found

.next:
    add di, 32
    loop .find_kernel

.not_found:
    mov si, msg_no_kernel
    call puts
    jmp wait_key_and_reboot

.found:
    mov ax, [di + 26]           ; первый кластер

    mov si, msg_found
    call puts

    ; грузим кластеры по цепочке FAT
    push es
    mov cx, KERNEL_LOAD_SEG
    mov es, cx
    mov bx, KERNEL_LOAD_OFF

.load_loop:
    push ax
    push bx

    ; LBA = DATA_START_LBA + (ax - 2) * SECTORS_PER_CLUSTER
    sub ax, 2
    add ax, DATA_START_LBA
    mov cx, 1
    call disk_read_multi

    pop bx
    pop ax

    push bx
    call fat_next_cluster
    pop bx

    ; продвигаем указатель es:bx на 512 байт вперёд
    add bx, 512
    jnc .no_overflow
    push ax
    mov ax, es
    add ax, 0x20
    mov es, ax
    xor bx, bx
    pop ax
.no_overflow:

    cmp ax, 0xFF8               ; конец цепочки кластеров
    jae .loaded
    jmp .load_loop

.loaded:
    pop es
    mov si, msg_jumping
    call puts

    mov dl, [ebr_drive_number]
    jmp KERNEL_LOAD_SEG:KERNEL_LOAD_OFF


;
; сравнивает 11-байтовое FAT-имя
; параметры:
;   - ds:si указывает на имя из FAT
;   - es:di указывает на искомое имя
; возвращает:
;   - CF=1, если совпали
;
fat_name_cmp:
    push si
    push di
    push cx
    mov cx, 11
.loop:
    lodsb
    cmp al, [di]
    jne .no
    inc di
    loop .loop
    pop cx
    pop di
    pop si
    stc
    ret
.no:
    pop cx
    pop di
    pop si
    clc
    ret


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
    push cx
    push bx
    mov cl, 1
    call disk_read
    pop bx
    pop cx
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
    push dx

    xor dx, dx
    div word [bdb_sectors_per_track]

    inc dx
    mov cx, dx

    xor dx, dx
    div word [bdb_heads]
    mov dh, dl
    mov ch, al
    shl ah, 6
    or cl, ah

    pop ax
    mov dl, al
    pop ax
    ret


;
; читает один сектор с диска
; параметры:
;   - ax: адрес LBA
;   - dl: номер диска
;   - es:bx: адрес в памяти, куда сохранить прочитанные данные
;
disk_read:
    push ax
    push bx
    push cx
    push dx
    push di

    push cx
    call lba_to_chs
    pop ax

    mov ah, 02h
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
; читает FAT и возвращает следующий кластер для кластера в ax
; параметры:
;   - ax: номер кластера
; возвращает:
;   - ax: следующий кластер (0xFFF = конец цепочки)
;
fat_next_cluster:
    push bx
    push cx
    push dx
    push si

    ; смещение в FAT: offset = cluster + cluster/2
    mov bx, ax
    shr bx, 1
    add bx, ax

    push bx
    mov ax, bx
    xor dx, dx
    mov cx, 512
    div cx
    add ax, FAT_START_LBA
    mov cx, dx
    mov bx, 0x8000
    push cx
    mov cl, 1
    call disk_read
    pop cx

    pop bx
    mov si, 0x8000
    add si, cx
    mov ax, [si]

    ; если bx чётное → младшие 12 бит, иначе → старшие 12 бит
    test bx, 1
    jz .even
    shr ax, 4
    jmp .done
.even:
    and ax, 0x0FFF
.done:
    pop si
    pop dx
    pop cx
    pop bx
    ret


;
; сбрасывает контроллер диска
; параметры:
;   - dl: номер диска
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

kernel_name:        db 'KERNEL  BIN'
msg_loading:        db 'Loading kernel...', ENDL, 0
msg_found:          db 'Kernel found.', ENDL, 0
msg_jumping:        db 'Jumping to kernel.', ENDL, 0
msg_no_kernel:      db 'KERNEL.BIN not found!', ENDL, 0
msg_read_failed:    db 'Read from disk failed!', ENDL, 0

times 510-($-$$) db 0
dw 0AA55h
