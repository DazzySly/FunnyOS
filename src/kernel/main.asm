org 0x1000
bits 16


%define ENDL 0x0D, 0x0A
%define MAX_CMD 64
%define HIST_SIZE 8

%define VGA_BASE 0xB800
%define SCREEN_COLS 80
%define SCREEN_ROWS 25

%define FS_TABLE_LBA    31
%define FS_DATA_LBA     32
%define FS_MAX_FILES    16
%define FS_ENTRY_SIZE   32
%define MAX_DATA_BUF    4096

; цвета
%define C_BLACK      0x00
%define C_BLUE       0x01
%define C_GREEN      0x02
%define C_CYAN       0x03
%define C_RED        0x04
%define C_MAGENTA    0x05
%define C_BROWN      0x06
%define C_GRAY       0x07
%define C_DGRAY      0x08
%define C_LBLUE      0x09
%define C_LGREEN     0x0A
%define C_LCYAN      0x0B
%define C_LRED       0x0C
%define C_LMAGENTA   0x0D
%define C_YELLOW     0x0E
%define C_WHITE      0x0F


start:
    jmp main


;
; выводит строку на экран
;
puts:
    push si
    push ax
.loop:
    lodsb
    or al, al
    jz .done
    call putc
    jmp .loop
.done:
    pop ax
    pop si
    ret


;
; выводит символ в VGA
;
putc:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    push word VGA_BASE
    pop es

    cmp al, 0x0A
    je .newline
    cmp al, 0x0D
    je .carriage
    cmp al, 0x08
    je .backspace

    push ax

    mov bx, [cursor_y]
    mov ax, SCREEN_COLS
    mul bx
    add ax, [cursor_x]
    shl ax, 1
    mov di, ax

    pop ax
    stosb
    mov al, [color_attr]
    stosb

    inc word [cursor_x]
    cmp word [cursor_x], SCREEN_COLS
    jb .done
    mov word [cursor_x], 0
    inc word [cursor_y]
    cmp word [cursor_y], SCREEN_ROWS
    jb .done
    call scroll_up
    jmp .done

.newline:
    mov word [cursor_x], 0
    inc word [cursor_y]
    cmp word [cursor_y], SCREEN_ROWS
    jb .done
    call scroll_up
    jmp .done

.carriage:
    mov word [cursor_x], 0
    jmp .done

.backspace:
    cmp word [cursor_x], 0
    je .done
    dec word [cursor_x]

    mov bx, [cursor_y]
    mov ax, SCREEN_COLS
    mul bx
    add ax, [cursor_x]
    shl ax, 1
    mov di, ax

    mov al, ' '
    stosb
    mov al, [color_attr]
    stosb
    jmp .done

.done:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


;
; очищает экран
;
clear_screen:
    push ax
    push cx
    push di
    push es

    push word VGA_BASE
    pop es

    mov di, 0
    mov cx, SCREEN_COLS * SCREEN_ROWS

    xor ax, ax
    mov al, ' '
    mov ah, [color_attr]

.clear:
    stosw
    loop .clear

    mov word [cursor_x], 0
    mov word [cursor_y], 0

    pop es
    pop di
    pop cx
    pop ax
    ret


;
; сдвигает экран на строку вверх
;
scroll_up:
    push ax
    push cx
    push si
    push di
    push es

    push word VGA_BASE
    pop es

    mov si, SCREEN_COLS * 2
    mov di, 0
    mov cx, SCREEN_COLS * (SCREEN_ROWS - 1)
.copy:
    mov ax, [es:si]
    mov [es:di], ax
    add si, 2
    add di, 2
    loop .copy

    mov di, SCREEN_COLS * (SCREEN_ROWS - 1) * 2
    mov cx, SCREEN_COLS

    xor ax, ax
    mov al, ' '
    mov ah, [color_attr]

.clear:
    stosw
    loop .clear

    mov word [cursor_y], SCREEN_ROWS - 1

    pop es
    pop di
    pop si
    pop cx
    pop ax
    ret


;
; печатает беззнаковое число из AX
;
print_dec:
    push ax
    push bx
    push cx
    push dx
    mov cx, 0
    mov bx, 10
.divide:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .divide
.print:
    pop dx
    mov al, dl
    add al, '0'
    call putc
    loop .print
    pop dx
    pop cx
    pop bx
    pop ax
    ret


;
; копирует строку si в di
;
str_copy:
.loop:
    lodsb
    stosb
    test al, al
    jnz .loop
    dec di
    ret


;
; пропускает пробелы по SI
;
skip_spaces:
    push ax
.loop:
    mov al, [si]
    cmp al, ' '
    jne .done
    inc si
    jmp .loop
.done:
    pop ax
    ret


;
; читает строку с клавиатуры
;
read_line:
    mov di, buffer
    mov word [hist_pos], HIST_SIZE
.read:
    mov ah, 0x00
    int 0x16
    cmp al, 0x0D
    je .done
    cmp al, 0x08
    je .backspace
    cmp ah, 0x48
    je .up
    cmp ah, 0x50
    je .down
    test al, al
    jz .read
    cmp di, buffer + MAX_CMD - 1
    je .read
    stosb
    call putc
    jmp .read
.backspace:
    cmp di, buffer
    je .read
    dec di
    call putc
    jmp .read
.up:
    cmp word [hist_pos], 0
    je .read
    dec word [hist_pos]
    call hist_load
    jmp .read
.down:
    cmp word [hist_pos], HIST_SIZE - 1
    jae .read
    inc word [hist_pos]
    call hist_load
    jmp .read
.done:
    mov al, 0
    stosb
    mov al, 0x0D
    call putc
    mov al, 0x0A
    call putc
    ret


;
; загружает историю по индексу [hist_pos]
;
hist_load:
    mov cx, di
    sub cx, buffer
    jcxz .nothing
.erase:
    mov al, 0x08
    call putc
    loop .erase
.nothing:

    mov ax, [hist_pos]
    mov bx, MAX_CMD
    mul bx
    add ax, hist_buf
    mov si, ax
    mov di, buffer
.copy:
    lodsb
    test al, al
    jz .done
    stosb
    call putc
    jmp .copy
.done:
    mov al, 0
    stosb
    ret


;
; сохраняет buffer в историю
;
hist_push:
    cmp byte [buffer], 0
    je .ret

    mov cx, HIST_SIZE - 1
    mov si, hist_buf + (HIST_SIZE - 2) * MAX_CMD
    mov di, hist_buf + (HIST_SIZE - 1) * MAX_CMD
.shift:
    push cx
    push si
    push di
    mov cx, MAX_CMD
.shift_byte:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    loop .shift_byte
    pop di
    pop si
    sub si, MAX_CMD
    sub di, MAX_CMD
    pop cx
    loop .shift

    mov si, buffer
    mov di, hist_buf
    call str_copy
.ret:
    mov word [hist_pos], HIST_SIZE
    ret


;
; сравнение без учёта регистра
;
strcmp_ci:
.loop:
    mov al, [si]
    mov bl, [di]
    cmp al, 'A'
    jb .a_done
    cmp al, 'Z'
    ja .a_done
    or al, 0x20
.a_done:
    cmp bl, 'A'
    jb .b_done
    cmp bl, 'Z'
    ja .b_done
    or bl, 0x20
.b_done:
    cmp al, bl
    jne .no
    test al, al
    jz .yes
    inc si
    inc di
    jmp .loop
.yes:
    stc
    ret
.no:
    clc
    ret


;
; проверка starts_with
;
starts_with:
    push si
    push di
.loop:
    mov al, [di]
    test al, al
    jz .yes
    mov bl, [si]
    cmp al, 'A'
    jb .a_done
    cmp al, 'Z'
    ja .a_done
    or al, 0x20
.a_done:
    cmp bl, 'A'
    jb .b_done
    cmp bl, 'Z'
    ja .b_done
    or bl, 0x20
.b_done:
    cmp al, bl
    jne .no
    inc si
    inc di
    jmp .loop
.yes:
    pop di
    pop si
    stc
    ret
.no:
    pop di
    pop si
    clc
    ret


;
; splash screen
;
splash_screen:
    push ax
    push si
    push cx
    push dx

    mov byte [color_attr], C_GRAY
    call clear_screen

    mov word [cursor_x], 0
    mov word [cursor_y], 0
    mov al, '+'
    call putc
    mov cx, 78
.top:
    mov al, '='
    call putc
    loop .top
    mov al, '+'
    call putc
    mov word [cursor_y], 24
    mov word [cursor_x], 0
    mov al, '+'
    call putc
    mov cx, 78
.bot:
    mov al, '='
    call putc
    loop .bot
    mov al, '+'
    call putc

    mov byte [color_attr], C_LCYAN
    mov word [cursor_x], 35
    mov word [cursor_y], 12
    mov si, splash_version
    call puts

    mov byte [color_attr], C_GRAY
    mov word [cursor_x], 36
    mov word [cursor_y], 16
    mov si, splash_loading
    call puts

    mov word [cursor_x], 32
    mov word [cursor_y], 17
    mov al, '['
    call putc
    mov cx, 14
.progress_empty:
    mov al, ' '
    call putc
    loop .progress_empty
    mov al, ']'
    call putc

    mov cx, 14
    mov word [progress_pos], 0
.progress_loop:
    push cx
    mov cx, 5
    call delay_50ms

    mov byte [color_attr], C_LGREEN
    mov ax, [progress_pos]
    add ax, 33
    mov [cursor_x], ax
    mov word [cursor_y], 17
    mov al, '#'
    call putc

    inc word [progress_pos]
    pop cx
    loop .progress_loop

    mov cx, 8
    call delay_50ms

    pop dx
    pop cx
    pop si
    pop ax
    ret


;
; пауза 50 мс * CX
;
delay_50ms:
    push ax
    push bx
    push cx
    push dx
    mov ax, cx
    mov bx, 50000
    mul bx
    mov cx, dx
    mov dx, ax
    mov ah, 0x86
    int 0x15
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; =========================================================
; Драйвер диска
; =========================================================

lba_to_chs:
    push ax
    push dx
    xor dx, dx
    div word [spt]
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


;
; читает 1 сектор: ax=LBA, es:bx=буфер
;
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
    int 0x13
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


;
; пишет 1 сектор: ax=LBA, es:bx=буфер
;
disk_write:
    push ax
    push bx
    push cx
    push dx
    push di

    mov di, bx
    call lba_to_chs
    mov dl, [disk_num]
    mov al, 1
    mov ah, 0x03
    mov bx, di
    mov di, 3

.retry:
    pusha
    stc
    int 0x13
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


disk_reset:
    pusha
    mov ah, 0
    stc
    int 0x13
    popa
    ret


; =========================================================
; MyFS
; =========================================================

fs_load:
    push bx
    push es
    push word 0
    pop es
    mov bx, fs_table
    mov ax, FS_TABLE_LBA
    call disk_read
    pop es
    pop bx
    ret


fs_save:
    push bx
    push es
    push word 0
    pop es
    mov bx, fs_table
    mov ax, FS_TABLE_LBA
    call disk_write
    pop es
    pop bx
    ret


;
; поиск файла: si=имя, di=запись или 0
;
fs_find:
    push si
    push cx
    mov di, fs_table
    mov cx, FS_MAX_FILES
.search:
    cmp byte [di], 0
    je .not_found
    cmp byte [di], 0xE5
    je .next
    push si
    push di
    call fs_name_cmp
    pop di
    pop si
    jc .found
.next:
    add di, FS_ENTRY_SIZE
    loop .search
.not_found:
    xor di, di
.found:
    pop cx
    pop si
    ret


;
; сравнение имён: si, di; CF=1 если равны
;
fs_name_cmp:
    push si
    push di
.loop:
    mov al, [si]
    mov bl, [di]
    cmp al, 'A'
    jb .a
    cmp al, 'Z'
    ja .a
    or al, 0x20
.a:
    cmp bl, 'A'
    jb .b
    cmp bl, 'Z'
    ja .b
    or bl, 0x20
.b:
    cmp al, bl
    jne .no
    test al, al
    jz .yes
    inc si
    inc di
    jmp .loop
.yes:
    pop di
    pop si
    stc
    ret
.no:
    pop di
    pop si
    clc
    ret


;
; свободная запись: di или 0
;
fs_free_slot:
    mov di, fs_table
    mov cx, FS_MAX_FILES
.search:
    cmp byte [di], 0
    je .found
    cmp byte [di], 0xE5
    je .found
    add di, FS_ENTRY_SIZE
    loop .search
    xor di, di
.found:
    ret


;
; свободный LBA после всех файлов: ax
;
fs_free_sector:
    push bx
    push cx
    push dx
    push di
    mov ax, FS_DATA_LBA
    mov bx, fs_table
    mov cx, FS_MAX_FILES
.scan:
    cmp byte [bx], 0
    je .next
    cmp byte [bx], 0xE5
    je .next
    mov dx, [bx + 20]
    mov di, [bx + 16]
    add di, 511
    shr di, 9
    add dx, di
    cmp dx, ax
    jbe .next
    mov ax, dx
.next:
    add bx, FS_ENTRY_SIZE
    loop .scan
    pop di
    pop dx
    pop cx
    pop bx
    ret


;
; создание файла: si=имя, di=данные, cx=размер
;
fs_create:
    push ax
    push bx
    push cx
    push dx
    push di
    push si
    push es

    mov [tmp_name], si
    mov [tmp_data], di
    mov [tmp_size], cx

    mov si, [tmp_name]
    call fs_find
    test di, di
    jnz .err

    call fs_free_slot
    test di, di
    jz .err

    mov bx, di

    mov si, [tmp_name]
    mov di, bx
    mov cx, 15
.cp_name:
    lodsb
    stosb
    test al, al
    jz .name_ok
    loop .cp_name
    mov byte [di], 0
.name_ok:

    mov ax, [tmp_size]
    mov [bx + 16], ax

    call fs_free_sector
    mov [bx + 20], ax

    push word 0
    pop es
    mov si, [tmp_data]
    mov cx, [tmp_size]
    add cx, 511
    shr cx, 9
.wr:
    push cx
    push ax
    push si
    mov bx, si
    call disk_write
    pop si
    pop ax
    pop cx
    add si, 512
    inc ax
    loop .wr

    call fs_save

    pop es
    pop si
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    clc
    ret

.err:
    pop es
    pop si
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    stc
    ret


;
; удаление файла: si=имя
;
fs_delete:
    push ax
    push bx
    push cx
    push dx
    push si
    call fs_find
    test di, di
    jz .err
    mov byte [di], 0xE5
    call fs_save
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    clc
    ret
.err:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    stc
    ret


; =========================================================
; Диспетчер команд
; =========================================================

process_command:
    cmp byte [buffer], 0
    je .ret

    mov si, buffer
    mov di, cmd_help_str
    call strcmp_ci
    jc cmd_help

    mov si, buffer
    mov di, cmd_ls_str
    call strcmp_ci
    jc cmd_ls

    mov si, buffer
    mov di, cmd_cat_str
    call starts_with
    jc cmd_cat

    mov si, buffer
    mov di, cmd_write_str
    call starts_with
    jc cmd_write

    mov si, buffer
    mov di, cmd_rm_str
    call starts_with
    jc cmd_rm

    mov si, buffer
    mov di, cmd_clear_str
    call strcmp_ci
    jc cmd_clear

    mov si, buffer
    mov di, cmd_cls_str
    call strcmp_ci
    jc cmd_clear

    mov si, buffer
    mov di, cmd_larp_str
    call strcmp_ci
    jc cmd_larp

    mov si, buffer
    mov di, cmd_mem_str
    call strcmp_ci
    jc cmd_mem

    mov si, buffer
    mov di, cmd_ver_str
    call strcmp_ci
    jc cmd_ver

    mov si, buffer
    mov di, cmd_reboot_str
    call strcmp_ci
    jc cmd_reboot

    mov si, buffer
    mov di, cmd_history_str
    call strcmp_ci
    jc cmd_history

    mov si, buffer
    mov di, cmd_color_str
    call strcmp_ci
    jc cmd_color

    mov si, buffer
    mov di, cmd_color_str
    call starts_with
    jc cmd_color

    mov si, buffer
    mov di, cmd_calc_str
    call strcmp_ci
    jc cmd_calc

    mov si, buffer
    mov di, cmd_calc_str
    call starts_with
    jc cmd_calc

    mov si, buffer
    mov di, cmd_beep_str
    call strcmp_ci
    jc cmd_beep

    mov si, buffer
    mov di, cmd_beep_str
    call starts_with
    jc cmd_beep

    mov si, buffer
    mov di, cmd_echo_str
    call strcmp_ci
    jc cmd_echo

    mov si, buffer
    mov di, cmd_echo_str
    call starts_with
    jc cmd_echo

    mov byte [color_attr], C_LRED
    mov si, msg_unknown
    call puts
    mov byte [color_attr], C_GRAY
.ret:
    ret


; =========================================================
; Команды
; =========================================================

cmd_help:
    mov byte [color_attr], C_LCYAN
    mov si, msg_help_body
    call puts
    ret

cmd_clear:
    call clear_screen
    ret

cmd_echo:
    mov si, buffer
    add si, 5
.skip_space:
    lodsb
    cmp al, ' '
    je .skip_space
    dec si
.print:
    lodsb
    test al, al
    jz .done
    call putc
    jmp .print
.done:
    mov al, 0x0D
    call putc
    mov al, 0x0A
    call putc
    ret

cmd_larp:
    mov byte [color_attr], C_YELLOW
    mov si, larp_art
    call puts
    mov byte [color_attr], C_GRAY
    ret

cmd_mem:
    mov si, msg_mem
    call puts
    int 0x12
    call print_dec
    mov si, msg_mem_kb
    call puts
    ret

cmd_ver:
    mov byte [color_attr], C_LCYAN
    mov si, msg_ver
    call puts
    mov byte [color_attr], C_GRAY
    ret


;
; ls — список файлов
;
cmd_ls:
    call fs_load
    mov di, fs_table
    mov cx, FS_MAX_FILES
    xor bx, bx
.loop:
    cmp byte [di], 0
    je .done
    cmp byte [di], 0xE5
    je .next
    inc bx

    push cx
    push di
    mov si, di
.pn:
    lodsb
    test al, al
    jz .nm_done
    call putc
    jmp .pn
.nm_done:
    mov ax, si
    sub ax, di
    mov cx, 20
    sub cx, ax
    jc .nopad
.pad:
    mov al, ' '
    call putc
    loop .pad
.nopad:
    pop di
    pop cx

    mov ax, [di + 16]
    call print_dec
    mov al, ' '
    call putc
    mov al, 'B'
    call putc
    mov al, 0x0D
    call putc
    mov al, 0x0A
    call putc
.next:
    add di, FS_ENTRY_SIZE
    loop .loop
.done:
    test bx, bx
    jnz .ret
    mov si, msg_no_files
    call puts
.ret:
    ret


;
; cat <file>
;
cmd_cat:
    mov si, buffer
    add si, 3
    call skip_spaces
    cmp byte [si], 0
    je .usage
    call fs_load
    call fs_find
    test di, di
    jz .nf
    mov cx, [di + 16]
    test cx, cx
    jz .done
    mov ax, [di + 20]
.rd:
    push cx
    push ax
    push word 0
    pop es
    mov bx, data_buffer
    call disk_read
    pop ax
    pop cx
    mov si, data_buffer
    mov dx, 512
    cmp cx, dx
    jb .short
    mov dx, cx
.short:
    lodsb
    call putc
    dec dx
    jnz .short
    sub cx, 512
    jbe .done
    inc ax
    jmp .rd
.done:
    mov al, 0x0D
    call putc
    mov al, 0x0A
    call putc
    ret
.nf:
    mov byte [color_attr], C_LRED
    mov si, msg_not_found
    call puts
    mov byte [color_attr], C_GRAY
    ret
.usage:
    mov byte [color_attr], C_LRED
    mov si, msg_cat_usage
    call puts
    mov byte [color_attr], C_GRAY
    ret


;
; write <file> <text>
;
cmd_write:
    mov si, buffer
    add si, 5
    call skip_spaces
    cmp byte [si], 0
    je .usage

    mov di, write_name
    mov cx, 15
.cn:
    mov al, [si]
    test al, al
    jz .usage
    cmp al, ' '
    je .cn_done
    stosb
    inc si
    loop .cn
.cn_done:
    mov byte [di], 0
    call skip_spaces
    cmp byte [si], 0
    je .usage

    mov di, data_buffer
    xor cx, cx
.cd:
    mov al, [si]
    test al, al
    jz .cd_done
    stosb
    inc si
    inc cx
    cmp cx, MAX_DATA_BUF
    jb .cd
.cd_done:
    mov byte [di], 0

    call fs_load
    mov si, write_name
    mov di, data_buffer
    call fs_create
    jc .err
    mov byte [color_attr], C_LGREEN
    mov si, msg_saved
    call puts
    mov byte [color_attr], C_GRAY
    ret
.err:
    mov byte [color_attr], C_LRED
    mov si, msg_write_err
    call puts
    mov byte [color_attr], C_GRAY
    ret
.usage:
    mov byte [color_attr], C_LRED
    mov si, msg_write_usage
    call puts
    mov byte [color_attr], C_GRAY
    ret


;
; rm <file>
;
cmd_rm:
    mov si, buffer
    add si, 2
    call skip_spaces
    cmp byte [si], 0
    je .usage
    call fs_load
    call fs_delete
    jc .err
    mov byte [color_attr], C_LGREEN
    mov si, msg_deleted
    call puts
    mov byte [color_attr], C_GRAY
    ret
.err:
    mov byte [color_attr], C_LRED
    mov si, msg_not_found
    call puts
    mov byte [color_attr], C_GRAY
    ret
.usage:
    mov byte [color_attr], C_LRED
    mov si, msg_rm_usage
    call puts
    mov byte [color_attr], C_GRAY
    ret


;
; color <0-15>
;
cmd_color:
    push ax
    push bx
    push cx
    push dx
    push si

    mov si, buffer
    add si, 5
    call skip_spaces

    cmp byte [si], 0
    je .usage

    call parse_num
    test dx, dx
    jz .usage

    cmp ax, 15
    ja .usage

    and ax, 0x0F
    mov [color_attr], al

    mov si, msg_color_set
    call puts
    mov ax, [color_attr]
    and ax, 0x0F
    call print_dec
    mov al, 0x0D
    call putc
    mov al, 0x0A
    call putc

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
.usage:
    mov byte [color_attr], C_LRED
    mov si, msg_color_usage
    call puts
    mov byte [color_attr], C_GRAY
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


;
; calc <a> <op> <b>
;
cmd_calc:
    push ax
    push bx
    push cx
    push dx
    push si

    mov si, buffer
    add si, 4
    call skip_spaces

    call parse_num
    test dx, dx
    jz .usage
    mov [calc_a], ax

    call skip_spaces

    mov al, [si]
    cmp al, '+'
    je .op_ok
    cmp al, '-'
    je .op_ok
    cmp al, '*'
    je .op_ok
    cmp al, '/'
    je .op_ok
    cmp al, '%'
    je .op_ok
    jmp .usage
.op_ok:
    mov [calc_op], al
    inc si

    call skip_spaces

    call parse_num
    test dx, dx
    jz .usage
    mov [calc_b], ax

    mov al, [calc_op]
    mov bx, [calc_a]
    mov cx, [calc_b]

    cmp al, '+'
    je .add
    cmp al, '-'
    je .sub
    cmp al, '*'
    je .mul
    cmp al, '/'
    je .div
    jmp .mod

.add:
    mov ax, bx
    add ax, cx
    jmp .print_result
.sub:
    mov ax, bx
    sub ax, cx
    jmp .print_result
.mul:
    mov ax, bx
    mul cx
    jmp .print_result
.div:
    cmp cx, 0
    je .div_zero
    mov ax, bx
    xor dx, dx
    div cx
    jmp .print_result
.mod:
    cmp cx, 0
    je .div_zero
    mov ax, bx
    xor dx, dx
    div cx
    mov ax, dx
    jmp .print_result
.div_zero:
    mov byte [color_attr], C_LRED
    mov si, msg_div_zero
    call puts
    mov byte [color_attr], C_GRAY
    jmp .done
.print_result:
    mov byte [color_attr], C_GRAY
    mov si, msg_calc_result
    call puts
    mov byte [color_attr], C_LGREEN
    call print_dec
    mov byte [color_attr], C_GRAY
    mov al, 0x0D
    call putc
    mov al, 0x0A
    call putc
.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
.usage:
    mov byte [color_attr], C_LRED
    mov si, msg_calc_usage
    call puts
    mov byte [color_attr], C_GRAY
    jmp .done


;
; beep
;
cmd_beep:
    push bx
    push cx
    push dx
    push si
    mov bx, 1000
    mov cx, 20
    mov si, buffer
    add si, 4
    call skip_spaces
    cmp byte [si], 0
    je .play
    call parse_num
    test dx, dx
    jz .play
    mov bx, ax
    cmp bx, 20000
    jbe .freq_ok
    mov bx, 1000
.freq_ok:
    call skip_spaces
    cmp byte [si], 0
    je .play
    call parse_num
    test dx, dx
    jz .play
    mov cx, 10
    xor dx, dx
    div cx
    test ax, ax
    jnz .have_ms
    mov ax, 1
.have_ms:
    mov cx, ax
.play:
    call speaker_tone
    pop si
    pop dx
    pop cx
    pop bx
    ret

speaker_tone:
    push ax
    push bx
    push cx
    push dx
    mov ax, 0x34DC
    mov dx, 0x0012
    div bx
    mov bx, ax
    mov al, 0xB6
    out 0x43, al
    mov al, bl
    out 0x42, al
    mov al, bh
    out 0x42, al
    in al, 0x61
    or al, 0x03
    out 0x61, al
    call speaker_delay
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    pop dx
    pop cx
    pop bx
    pop ax
    ret

speaker_delay:
    push ax
    push bx
    push cx
    push dx
    mov ax, cx
    mov bx, 10000
    mul bx
    mov cx, dx
    mov dx, ax
    mov ah, 0x86
    int 0x15
    pop dx
    pop cx
    pop bx
    pop ax
    ret


;
; reboot
;
cmd_reboot:
    mov cx, 0xFFFF
.wait_input:
    in al, 0x64
    test al, 0x02
    jz .send_reset
    loop .wait_input
.send_reset:
    mov al, 0xFE
    out 0x64, al
.halt:
    cli
    hlt
    jmp .halt


;
; history
;
cmd_history:
    mov byte [color_attr], C_LCYAN
    mov cx, HIST_SIZE
    mov si, hist_buf
.line:
    push cx
    push si
    cmp byte [si], 0
    je .next
    mov si, msg_hist_prefix
    call puts
    pop si
    push si
    call puts
    mov al, 0x0D
    call putc
    mov al, 0x0A
    call putc
.next:
    pop si
    add si, MAX_CMD
    pop cx
    loop .line
    mov byte [color_attr], C_GRAY
    ret


;
; мелодия при запуске
;
boot_melody:
    mov bx, 400
    mov cx, 10
    call speaker_tone
    mov bx, 800
    mov cx, 10
    call speaker_tone
    mov bx, 1200
    mov cx, 15
    call speaker_tone
    ret


;
; парсит число из SI в AX
;
parse_num:
    push bx
    push cx
    xor bx, bx
    xor dx, dx
.loop:
    mov al, [si]
    cmp al, '0'
    jb .done
    cmp al, '9'
    ja .done
    push ax
    mov ax, bx
    mov cx, 10
    mul cx
    mov bx, ax
    pop ax
    sub al, '0'
    mov ah, 0
    add bx, ax
    inc si
    inc dx
    jmp .loop
.done:
    mov ax, bx
    pop cx
    pop bx
    ret


;
; main
;
main:
    mov ax, 0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov ah, 0x01
    mov cx, 0x2000
    int 0x10

    mov [disk_num], dl

    mov word [cursor_x], 0
    mov word [cursor_y], 0
    mov byte [color_attr], C_GRAY

    mov di, hist_buf
    mov cx, HIST_SIZE * MAX_CMD
    xor al, al
    rep stosb

    mov word [hist_pos], HIST_SIZE

    call splash_screen

    mov byte [color_attr], C_GRAY
    call clear_screen

    call boot_melody

    mov byte [color_attr], C_LCYAN
    mov si, msg_welcome_1
    call puts

.main_loop:
    mov byte [color_attr], C_LGREEN
    mov si, prompt
    call puts
    mov byte [color_attr], C_WHITE

    call read_line
    call hist_push

    mov byte [color_attr], C_GRAY
    call process_command
    jmp .main_loop


;
; данные
;

prompt:         db 'FunnyOS> ', 0
msg_welcome_1:  db 'FunnyOS v1.0', ENDL
msg_welcome_2:  db 'Type "help" for commands.', ENDL, ENDL, 0

msg_help_title: db 'Commands:', ENDL, 0
msg_help_body:  db '  echo <text>       - print text', ENDL
                db '  ls                - list files', ENDL
                db '  cat <file>        - print file', ENDL
                db '  write <f> <text>  - create file', ENDL
                db '  rm <file>         - delete file', ENDL
                db '  calc <a> <op> <b> - calculator (* + - / %) 65535 - max', ENDL
                db '  larp              - GIGA larp', ENDL
                db '  mem               - show memory size', ENDL
                db '  beep [hz] [ms]    - beep boop', ENDL
                db '  color <0-15>      - set text color', ENDL
                db '  ver               - show version', ENDL
                db '  reboot            - reboot Lol', ENDL
                db '  history           - show history', ENDL
                db '  help              - get help.', ENDL
                db '  clear / cls       - clear screen', ENDL, 0

msg_unknown:    db 'Unknown command', ENDL, 0
msg_mem:        db 'Memory: ', 0
msg_mem_kb:     db ' KB', ENDL, 0
msg_hist_prefix: db '  ', 0
msg_color_usage: db 'Usage: color <0-15>', ENDL, 0
msg_color_set:   db 'Color: ', 0
msg_calc_usage:  db 'Usage: calc <a> <op> <b>', ENDL
                 db 'a, b: 0..65535', ENDL
                 db 'Ops: * + - / %', ENDL, 0
msg_calc_result: db '= ', 0
msg_div_zero:    db 'Error: division by zero', ENDL, 0
msg_no_files:    db 'No files.', ENDL, 0
msg_not_found:   db 'File not found.', ENDL, 0
msg_saved:       db 'Saved.', ENDL, 0
msg_deleted:     db 'Deleted.', ENDL, 0
msg_write_err:   db 'Write error.', ENDL, 0
msg_cat_usage:   db 'Usage: cat <file>', ENDL, 0
msg_write_usage: db 'Usage: write <file> <text>', ENDL, 0
msg_rm_usage:    db 'Usage: rm <file>', ENDL, 0
msg_ver:        db 'FunnyOS 1.0', ENDL
                db 'Boot: BIOS, 2-stage loader, USB-HDD', ENDL
                db 'Display: VGA text 80x25 direct', ENDL
                db 'Filesystem: MyFS', ENDL
                db 'Build: ', __DATE__, ' ', __TIME__, ENDL, 0

cmd_echo_str:    db 'echo', 0
cmd_help_str:    db 'help', 0
cmd_clear_str:   db 'clear', 0
cmd_cls_str:     db 'cls', 0
cmd_larp_str:    db 'larp', 0
cmd_mem_str:     db 'mem', 0
cmd_beep_str:    db 'beep', 0
cmd_color_str:   db 'color', 0
cmd_calc_str:    db 'calc', 0
cmd_ver_str:     db 'ver', 0
cmd_reboot_str:  db 'reboot', 0
cmd_history_str: db 'history', 0
cmd_ls_str:      db 'ls', 0
cmd_cat_str:     db 'cat', 0
cmd_write_str:   db 'write', 0
cmd_rm_str:      db 'rm', 0

splash_version: db 'FunnyOS 1.0', 0
splash_loading: db 'Loading...', 0

larp_art:
    db '  +======================================+', ENDL
    db '  |                                      |', ENDL
    db '  |   ##      ###    ######    ######    |', ENDL
    db '  |   ##     ## ##   ##   ##   ##   ##   |', ENDL
    db '  |   ##     ## ##   ##   ##   ##   ##   |', ENDL
    db '  |   ##     #####   ######    ######    |', ENDL
    db '  |   ##     ## ##   ##   ##   ##        |', ENDL
    db '  |   #####  ## ##   ##   ##   ##        |', ENDL
    db '  |   #####  ## ##   ##   ##   ##        |', ENDL
    db '  |                                      |', ENDL
    db '  |             ~ L A R P ~              |', ENDL
    db '  |                                      |', ENDL
    db '  |          the ancient art of          |', ENDL
    db '  |       pretending to be something     |', ENDL
    db '  |             you are not              |', ENDL
    db '  |                                      |', ENDL
    db '  |                   (lirili lariLARP)  |', ENDL
    db '  |                                      |', ENDL
    db '  +======================================+', ENDL, 0

;
; переменные и буферы
;
disk_num:        db 0
spt:             dw 18
heads:           dw 2

cursor_x:        dw 0
cursor_y:        dw 0
color_attr:      db C_GRAY

progress_pos:    dw 0

calc_a:          dw 0
calc_b:          dw 0
calc_op:         db 0

tmp_name:        dw 0
tmp_data:        dw 0
tmp_size:        dw 0

write_name:      times 16 db 0

buffer:          times MAX_CMD db 0
cur_pos:         dw 0
hist_pos:        dw HIST_SIZE
hist_buf:        times HIST_SIZE * MAX_CMD db 0

fs_table:        times 512 db 0
data_buffer:     times MAX_DATA_BUF db 0
