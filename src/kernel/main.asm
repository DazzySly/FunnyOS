org 0x1000
bits 16


%define ENDL 0x0D, 0x0A
%define MAX_CMD 64
%define HIST_SIZE 8


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


;
; выводит один символ из al
;
putc:
    mov ah, 0x0E
    mov bh, 0
    int 0x10
    ret


;
; выводит беззнаковое число из ax в десятичном виде
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
; копирует строку si в di (с нуль-терминатором)
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
; читает строку с клавиатуры в buffer, поддерживает стрелки
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
    mov al, 0x08
    call putc
    mov al, ' '
    call putc
    mov al, 0x08
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
; стирает текущий ввод и загружает историю по индексу [hist_pos]
;
hist_load:
    ; стираем символы с экрана
    mov cx, di
    sub cx, buffer
    jcxz .nothing
.erase:
    mov al, 0x08
    call putc
    mov al, ' '
    call putc
    mov al, 0x08
    call putc
    loop .erase
.nothing:

    ; загружаем строку из истории
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

    ; сдвигаем записи вниз
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

    ; копируем buffer в первую ячейку
    mov si, buffer
    mov di, hist_buf
    call str_copy

.ret:
    mov word [hist_pos], HIST_SIZE
    ret


;
; сравнивает две строки без учёта регистра
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
; проверяет, начинается ли строка si с di
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
; диспетчер команд
;
process_command:
    cmp byte [buffer], 0
    je .ret

    call hist_push

    mov si, buffer
    mov di, cmd_help_str
    call strcmp_ci
    jc cmd_help

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
    mov di, cmd_reboot_str
    call strcmp_ci
    jc cmd_reboot

    mov si, buffer
    mov di, cmd_history_str
    call strcmp_ci
    jc cmd_history

    mov si, buffer
    mov di, cmd_echo_str
    call strcmp_ci
    jc cmd_echo

    mov si, buffer
    mov di, cmd_echo_str
    call starts_with
    jc cmd_echo

    mov si, msg_unknown
    call puts

.ret:
    ret


;
; команда help
;
cmd_help:
    mov si, msg_help
    call puts
    ret


;
; команда clear (и cls)
;
cmd_clear:
    mov ax, 0x0003
    int 0x10
    ret


;
; команда echo — вывести текст
;
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


;
; команда larp — ASCII-рамка
;
cmd_larp:
    mov si, larp_art
    call puts
    ret


;
; команда mem — сколько памяти видит BIOS
;
cmd_mem:
    int 0x12
    mov si, msg_mem
    call puts
    call print_dec
    mov si, msg_mem_kb
    call puts
    ret


;
; команда reboot — перезагрузка
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
; команда history — показать историю
;
cmd_history:
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
    ret


;
; главная функция
;
main:
    mov ax, 0
    mov ds, ax
    mov es, ax

    mov ss, ax
    mov sp, 0x7C00

    ; инициализация истории — все пустые
    mov di, hist_buf
    mov cx, HIST_SIZE * MAX_CMD
    xor al, al
    rep stosb

    mov word [hist_pos], HIST_SIZE

    mov si, msg_welcome
    call puts

.main_loop:
    mov si, prompt
    call puts

    call read_line
    call process_command
    jmp .main_loop


;
; данные
;

prompt:         db '> ', 0
msg_welcome:    db 'FunnyOS v0.2', ENDL
                db 'Type "help" for commands.', ENDL, ENDL, 0
msg_help:       db 'Commands:', ENDL
                db '  echo <text>  - print text', ENDL
                db '  larp         - GIGA larp', ENDL
                db '  mem          - show memory size', ENDL
                db '  reboot       - reboot LOL', ENDL
                db '  history      - show command history', ENDL
                db '  help         - this help', ENDL
                db '  clear / cls  - clear screen', ENDL, 0
msg_unknown:    db 'Unknown command', ENDL, 0
msg_mem:        db 'Memory: ', 0
msg_mem_kb:     db ' KB', ENDL, 0
msg_hist_prefix: db '  ', 0

cmd_echo_str:    db 'echo', 0
cmd_help_str:    db 'help', 0
cmd_clear_str:   db 'clear', 0
cmd_cls_str:     db 'cls', 0
cmd_larp_str:    db 'larp', 0
cmd_mem_str:     db 'mem', 0
cmd_reboot_str:  db 'reboot', 0
cmd_history_str: db 'history', 0


; ========== larp арт (строка 333) ==========

larp_art:
    db '  +======================================+', ENDL
    db '  |                                      |', ENDL
    db '  |   ##      ###    ######    ######    |', ENDL
    db '  |   ##     ## ##   ##   ##   ##   ##   |', ENDL
    db '  |   ##     ## ##   ##   ##   ##   ##   |', ENDL
    db '  |   ##     #####   ######    ######    |', ENDL
    db '  |   ##     ## ##   ##   ##   ##        |', ENDL
    db '  |   ##     ## ##   ##   ##   ##        |', ENDL
    db '  |    ####  ## ##   ##   ##   ##        |', ENDL
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


buffer:         times MAX_CMD db 0
cur_pos:        dw 0
hist_pos:       dw HIST_SIZE
hist_buf:       times HIST_SIZE * MAX_CMD db 0
