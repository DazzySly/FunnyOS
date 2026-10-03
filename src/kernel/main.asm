org 0x1000
bits 16


%define ENDL 0x0D, 0x0A
%define MAX_CMD 64


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
; читает строку с клавиатуры в buffer
;
read_line:
    mov di, buffer

.read:
    mov ah, 0x00
    int 0x16

    cmp al, 0x0D
    je .done

    cmp al, 0x08
    je .backspace

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

.done:
    mov al, 0
    stosb
    mov al, 0x0D
    call putc
    mov al, 0x0A
    call putc
    ret


;
; сравнивает две строки без учёта регистра
; параметры:
;   - si — первая строка
;   - di — вторая строка
; возвращает:
;   - CF=1, если строки равны
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
; возвращает CF=1, если да
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

    mov si, buffer
    mov di, cmd_help_str
    call strcmp_ci
    jc cmd_help

    mov si, buffer
    mov di, cmd_clear_str
    call strcmp_ci
    jc cmd_clear

    mov si, buffer
    mov di, cmd_larp_str
    call strcmp_ci
    jc cmd_larp

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
; команда clear
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
; главная функция
;
main:
    mov ax, 0
    mov ds, ax
    mov es, ax

    mov ss, ax
    mov sp, 0x7C00

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
msg_welcome:    db 'FunnyOS v0.1', ENDL
                db 'Type "help" for commands.', ENDL, ENDL, 0
msg_help:       db 'Commands:', ENDL
                db '  echo <text>  - print text', ENDL
                db '  larp         - GIGA larp', ENDL
                db '  help         - this help', ENDL
                db '  clear        - clear screen', ENDL, 0
msg_unknown:    db 'Unknown command', ENDL, 0

cmd_echo_str:   db 'echo', 0
cmd_help_str:   db 'help', 0
cmd_clear_str:  db 'clear', 0
cmd_larp_str:   db 'larp', 0

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
