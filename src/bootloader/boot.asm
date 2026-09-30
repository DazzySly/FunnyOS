org 0x7C00
bits 16


%define ENDL 0x0D, 0x0A


;
; заголовок FAT12
; 
jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'           ; 8 байт
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880                 ; 2880 * 512 = 1.44 МБ
bdb_media_descriptor_type:  db 0F0h                 ; F0 = дискета 3.5"
bdb_sectors_per_fat:        dw 9                    ; 9 секторов на FAT
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

; расширенная загрузочная запись
ebr_drive_number:           db 0                    ; 0x00 дискета, 0x80 жёсткий диск, бесполезно
                            db 0                    ; зарезервировано
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h   ; серийный номер, значение не важно
ebr_volume_label:           db 'NANOBYTE OS'        ; 11 байт, дополнено пробелами
ebr_system_id:              db 'FAT12   '           ; 8 байт

;
; здесь начинается код
;

start:
    jmp main


;
; выводит строку на экран
; параметры:
;   - ds:si указывает на строку
;
puts:
    ; сохраняем регистры, которые будем изменять
    push si
    push ax
    push bx

.loop:
    lodsb               ; загружаем следующий символ в al
    or al, al           ; проверяем, не нулевой ли следующий символ?
    jz .done

    mov ah, 0x0E        ; вызов прерывания bios
    mov bh, 0           ; устанавливаем номер страницы в 0
    int 0x10

    jmp .loop

.done:
    pop bx
    pop ax
    pop si    
    ret
    

main:
    ; настраиваем сегменты данных
    mov ax, 0                   ; нельзя задать ds/es напрямую
    mov ds, ax
    mov es, ax
    
    ; настраиваем стек
    mov ss, ax
    mov sp, 0x7C00              ; стек растёт вниз от места, куда мы загружены

    ; читаем что-нибудь с дискеты
    ; bios должен установить dl в номер диска
    mov [ebr_drive_number], dl

    mov ax, 1                   ; LBA=1, второй сектор диска
    mov cl, 1                   ; читаем 1 сектор
    mov bx, 0x7E00              ; данные должны быть после загрузчика
    call disk_read

    ; выводим приветственное сообщение
    mov si, msg_hello
    call puts

    cli                         ; отключаем прерывания, так процессор не сможет выйти из состояния "halt"
    hlt


;
; обработчики ошибок
;

floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0
    int 16h                     ; ждём нажатия клавиши
    jmp 0FFFFh:0                ; переходим в начало bios, должен произойти перезапуск

.halt:
    cli                         ; отключаем прерывания, так процессор не сможет выйти из состояния "halt"
    hlt


;
; процедуры работы с диском
;

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

    xor dx, dx                          ; dx = 0
    div word [bdb_sectors_per_track]    ; ax = LBA / секторов_на_дорожке
                                        ; dx = LBA % секторов_на_дорожке

    inc dx                              ; dx = (LBA % секторов_на_дорожке + 1) = сектор
    mov cx, dx                          ; cx = сектор

    xor dx, dx                          ; dx = 0
    div word [bdb_heads]                ; ax = (LBA / секторов_на_дорожке) / головок = цилиндр
                                        ; dx = (LBA / секторов_на_дорожке) % головок = головка
    mov dh, dl                          ; dh = головка
    mov ch, al                          ; ch = цилиндр (младшие 8 бит)
    shl ah, 6
    or cl, ah                           ; помещаем старшие 2 бита цилиндра в CL

    pop ax
    mov dl, al                          ; восстанавливаем DL
    pop ax
    ret


;
; читает секторы с диска
; параметры:
;   - ax: адрес LBA
;   - cl: количество секторов для чтения (до 128)
;   - dl: номер диска
;   - es:bx: адрес в памяти, куда сохранить прочитанные данные
;
disk_read:

    push ax                             ; сохраняем регистры, которые будем изменять
    push bx
    push cx
    push dx
    push di

    push cx                             ; временно сохраняем CL (количество секторов для чтения)
    call lba_to_chs                     ; вычисляем CHS
    pop ax                              ; AL = количество секторов для чтения
    
    mov ah, 02h
    mov di, 3                           ; количество попыток

.retry:
    pusha                               ; сохраняем все регистры, мы не знаем, что изменяет bios
    stc                                 ; устанавливаем флаг переноса, некоторые bios его не устанавливают
    int 13h                             ; флаг переноса сброшен = успех
    jnc .done                           ; переход, если флаг переноса не установлен

    ; чтение не удалось
    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    ; все попытки исчерпаны
    jmp floppy_error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax                             ; восстанавливаем изменённые регистры
    ret


;
; сбрасывает контроллер диска
; параметры:
;   dl: номер диска
;
disk_reset:
    pusha
    mov ah, 0
    stc
    int 13h
    jc floppy_error
    popa
    ret


msg_hello:              db 'Hello world!', ENDL, 0
msg_read_failed:        db 'Read from disk failed!', ENDL, 0

times 510-($-$$) db 0
dw 0AA55h
