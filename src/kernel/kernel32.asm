org 0x1000
bits 32

%define VGA_BASE 0xB8000
%define VGA_COLS 80
%define VGA_ROWS 25

section .text

start:
    call vga_clear

    mov byte [color_attr], 0x0B
    mov esi, msg_header
    call vga_puts

    mov byte [color_attr], 0x07
    mov esi, msg_init
    call vga_puts

    call idt_init
    mov esi, msg_idt
    call vga_puts

    call pic_remap
    mov esi, msg_pic
    call vga_puts

    call keyboard_init
    mov esi, msg_kbd
    call vga_puts

    sti
    mov esi, msg_ready
    call vga_puts

    mov byte [color_attr], 0x0A
    mov esi, msg_prompt
    call vga_puts
    mov byte [color_attr], 0x0F

.main_loop:
    call keyboard_getchar
    test al, al
    jz .main_loop

    cmp al, 0x0A
    je .newline
    cmp al, 0x08
    je .backspace

    call vga_putc
    jmp .main_loop

.newline:
    mov al, 0x0A
    call vga_putc
    mov byte [color_attr], 0x0A
    mov esi, msg_prompt
    call vga_puts
    mov byte [color_attr], 0x0F
    jmp .main_loop

.backspace:
    call vga_backspace
    jmp .main_loop


; ============ VGA ============

vga_clear:
    push edi
    push ecx
    push eax
    mov edi, VGA_BASE
    mov ecx, VGA_COLS * VGA_ROWS
    mov ax, 0x0720
.clr:
    mov [edi], ax
    add edi, 2
    loop .clr
    mov dword [cursor], 0
    pop eax
    pop ecx
    pop edi
    ret


vga_putc:
    push eax
    push ebx
    push edi

    cmp al, 0x0A
    je .newline
    cmp al, 0x0D
    je .cr

    mov edi, [cursor]
    shl edi, 1              ; ← УМНОЖАЕМ НА 2
    add edi, VGA_BASE
    mov bl, [color_attr]
    mov [edi], al
    mov [edi + 1], bl

    inc dword [cursor]
    cmp dword [cursor], VGA_COLS * VGA_ROWS
    jb .done
    call vga_scroll
    jmp .done

.newline:
    mov eax, [cursor]
    xor edx, edx
    mov ebx, VGA_COLS
    div ebx
    inc eax
    mul ebx
    mov [cursor], eax
    cmp eax, VGA_COLS * VGA_ROWS
    jb .done
    call vga_scroll
    jmp .done

.cr:
    mov eax, [cursor]
    xor edx, edx
    mov ebx, VGA_COLS
    div ebx
    mul ebx
    mov [cursor], eax

.done:
    pop edi
    pop ebx
    pop eax
    ret

vga_puts:
    push eax
    push esi
.loop:
    movzx eax, byte [esi]
    test al, al
    jz .done
    push esi
    call vga_putc
    pop esi
    inc esi
    jmp .loop
.done:
    pop esi
    pop eax
    ret


vga_backspace:
    push eax
    push ebx
    push edi
    cmp dword [cursor], 0
    je .done
    dec dword [cursor]
    mov edi, [cursor]
    shl edi, 1
    add edi, VGA_BASE
    mov byte [edi], ' '
    mov bl, [color_attr]
    mov [edi + 1], bl
.done:
    pop edi
    pop ebx
    pop eax
    ret

vga_scroll:
    push edi
    push esi
    push ecx
    push eax
    mov esi, VGA_BASE + VGA_COLS * 2
    mov edi, VGA_BASE
    mov ecx, VGA_COLS * (VGA_ROWS - 1)
.copy:
    mov ax, [esi]
    mov [edi], ax
    add esi, 2
    add edi, 2
    loop .copy
    mov ecx, VGA_COLS
    mov ax, 0x0720
.clear:
    mov [edi], ax
    add edi, 2
    loop .clear
    mov eax, [cursor]
    sub eax, VGA_COLS
    mov [cursor], eax
    pop eax
    pop ecx
    pop esi
    pop edi
    ret


; ============ IDT ============

idt_init:
    push eax
    push ecx
    push edi
    push edx

    mov ecx, 256
    mov edi, idt_entries
.fill:
    mov eax, isr_default
    mov word [edi], ax
    mov word [edi + 2], 0x08
    mov byte [edi + 4], 0
    mov byte [edi + 5], 0x8E
    shr eax, 16
    mov word [edi + 6], ax
    add edi, 8
    loop .fill

    call set_exception_handlers
    call set_irq_handlers

    lidt [idt_descriptor]

    pop edx
    pop edi
    pop ecx
    pop eax
    ret


set_exception_handlers:
    push eax
    push edx
    mov eax, 0
.loop:
    cmp eax, 32
    jae .done
    mov edx, [isr_table + eax * 4]
    call set_idt_entry
    inc eax
    jmp .loop
.done:
    pop edx
    pop eax
    ret


set_irq_handlers:
    push eax
    push edx
    mov eax, 0
.loop:
    cmp eax, 16
    jae .done
    mov edx, [irq_table + eax * 4]
    push eax
    add eax, 32
    call set_idt_entry
    pop eax
    inc eax
    jmp .loop
.done:
    pop edx
    pop eax
    ret


set_idt_entry:
    push eax
    push edi
    shl eax, 3
    mov edi, idt_entries
    add edi, eax
    mov eax, edx
    mov word [edi], ax
    mov word [edi + 2], 0x08
    mov byte [edi + 4], 0
    mov byte [edi + 5], 0x8E
    shr eax, 16
    mov word [edi + 6], ax
    pop edi
    pop eax
    ret


pic_remap:
    push eax
    mov al, 0x11
    out 0x20, al
    out 0xA0, al

    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al

    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al

    mov al, 0x01
    out 0x21, al
    out 0xA1, al

    mov al, 0xFC
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al
    pop eax
    ret


; ============ ISR ============

isr_default:
    pusha
    mov byte [color_attr], 0x0C
    mov esi, msg_exception
    call vga_puts
    mov byte [color_attr], 0x07
.halt:
    cli
    hlt
    jmp .halt


isr_divide:
    pusha
    mov byte [color_attr], 0x0C
    mov esi, msg_div_zero
    call vga_puts
    mov byte [color_attr], 0x07
.halt:
    cli
    hlt
    jmp .halt


isr_gpf:
    pusha
    mov byte [color_attr], 0x0C
    mov esi, msg_gpf
    call vga_puts
    mov byte [color_attr], 0x07
.halt:
    cli
    hlt
    jmp .halt


; ============ IRQ ============

irq0_handler:
    pusha
    inc dword [timer_ticks]
    mov al, 0x20
    out 0x20, al
    popa
    iret


irq1_handler:
    pusha
    in al, 0x60
    test al, 0x80
    jnz .done
    movzx eax, al
    mov bl, [keymap + eax]
    test bl, bl
    jz .done
    mov eax, [kbd_write]
    mov [kbd_buffer + eax], bl
    inc eax
    and eax, 63
    mov [kbd_write], eax
.done:
    mov al, 0x20
    out 0x20, al
    popa
    iret


; ============ Keyboard ============

keyboard_init:
    ret


keyboard_getchar:
    push ebx
    mov eax, [kbd_read]
    cmp eax, [kbd_write]
    je .empty
    mov bl, [kbd_buffer + eax]
    inc eax
    and eax, 63
    mov [kbd_read], eax
    mov al, bl
    pop ebx
    ret
.empty:
    xor al, al
    pop ebx
    ret


; ============ Data ============

section .data

color_attr:  db 0x07
cursor:      dd 0

msg_header:  db 'FunnyOS 32-bit v0.2', 0x0A, 0
msg_init:    db 'Initializing...', 0x0A, 0
msg_idt:     db '  IDT loaded', 0x0A, 0
msg_pic:     db '  PIC remapped', 0x0A, 0
msg_kbd:     db '  Keyboard ready', 0x0A, 0
msg_ready:   db 'Ready. Type something!', 0x0A, 0
msg_prompt:  db '> ', 0

msg_exception:  db 'EXCEPTION!', 0x0A, 0
msg_div_zero:   db 'DIVIDE BY ZERO!', 0x0A, 0
msg_gpf:        db 'GENERAL PROTECTION FAULT!', 0x0A, 0

timer_ticks:  dd 0

kbd_buffer:   times 64 db 0
kbd_write:    dd 0
kbd_read:     dd 0

align 8
idt_entries:  times 256 * 8 db 0

idt_descriptor:
    dw 256 * 8 - 1
    dd idt_entries

align 4
isr_table:
    dd isr_divide
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_gpf
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default

irq_table:
    dd irq0_handler
    dd irq1_handler
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default
    dd isr_default

keymap:
    db 0, 27, '1', '2', '3', '4', '5', '6'
    db '7', '8', '9', '0', '-', '=', 8, 9
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i'
    db 'o', 'p', '[', ']', 10, 0, 'a', 's'
    db 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';'
    db 39, '`', 0, 92, 'z', 'x', 'c', 'v'
    db 'b', 'n', 'm', ',', '.', '/', 0, '*'
    db 0, ' ', 0, 0, 0, 0, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, '7'
    db '8', '9', '-', '4', '5', '6', '+', '1'
    db '2', '3', '0', '.', 0, 0, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0
