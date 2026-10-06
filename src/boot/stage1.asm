org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A
%define STAGE2_LBA      1
%define STAGE2_SECTORS  7
%define STAGE2_ADDR     0x7E00

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
ebr_volume_label:           db 'FUNNYOS32  '
ebr_system_id:              db 'FAT12   '

start:
    jmp main

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

    mov si, msg_stage1
    call puts

    mov ax, STAGE2_LBA
    mov cx, STAGE2_SECTORS
    mov bx, STAGE2_ADDR
    call disk_read_multi
    jc floppy_error

    mov si, msg_jump
    call puts

    mov dl, [ebr_drive_number]
    jmp 0x0000:STAGE2_ADDR

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
    div word [bdb_sectors_per_track]
    inc dx
    mov cx, dx
    xor dx, dx
    div word [bdb_heads]
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

floppy_error:
    mov si, msg_read_failed
    call puts
.halt:
    cli
    hlt
    jmp .halt

msg_stage1:      db 'Stage1: loading...', ENDL, 0
msg_jump:        db 'Stage1: jumping to stage2', ENDL, 0
msg_read_failed: db 'Stage1: read failed!', ENDL, 0

times 510-($-$$) db 0
dw 0AA55h
