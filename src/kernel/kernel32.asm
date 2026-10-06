org 0x1000
bits 32

%define VGA_BASE 0xB8000
%define ENDL 0x0D, 0x0A

start:
    ; очистка VGA
    call clear_screen

    ; вывод заголовка
    mov esi, msg_header
    mov edi, VGA_BASE
    mov ah, 0x0B            ; ярко-голубой на чёрном
    call puts32

    ; вывод строки
    mov edi, VGA_BASE + 80*2*2
    mov ah, 0x0A            ; ярко-зелёный
    mov esi, msg_body
    call puts32

    ; строка 3
    mov edi, VGA_BASE + 80*2*4
    mov ah, 0x0E            ; жёлтый
    mov esi, msg_wait
    call puts32

.halt:
    cli
    hlt
    jmp .halt


;
; очищает экран (80x25)
;
clear_screen:
    push edi
    push ecx
    push ax

    mov edi, VGA_BASE
    mov ecx, 80 * 25
    mov ax, 0x0720          ; пробел + серый атрибут
.clr:
    mov [edi], ax
    add edi, 2
    loop .clr

    pop ax
    pop ecx
    pop edi
    ret


;
; выводит строку
;   - ESI: строка
;   - EDI: куда
;   - AH: атрибут
;
puts32:
    push eax
    push esi
    push edi
.loop:
    mov al, [esi]
    test al, al
    jz .done
    cmp al, 0x0A
    je .newline
    mov [edi], al
    mov [edi + 1], ah
    add edi, 2
    inc esi
    jmp .loop
.newline:
    ; переход на новую строку: EDI должен быть выровнен на 160
    ; упрощённо — не используем в этом тесте
    inc esi
    jmp .loop
.done:
    pop edi
    pop esi
    pop eax
    ret


;
; данные
;
msg_header:  db 'FunnyOS 32-bit v0.1', 0
msg_body:    db 'Protected mode is working!', 0
msg_wait:    db 'Kernel loaded at 0x1000', 0
