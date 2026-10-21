; PV-1000 Control Test: a Casio PV-1000 test ROM (8 KB) that shows the state of both
; controllers, read from the joystick matrix (port 0xFD) the way the games do.
;
; The title is white on a blue bar. A frame counter next to the matrix rows shows that the
; program is running. Each label lights up (yellow on a red bar) while its button is held,
; a beep plays while anything is held (controller 1 on sound channel 1, controller 2 on
; channel 2, in different tones), and the four raw matrix rows are shown in hexadecimal,
; the whole byte read from port 0xFD.
;
; Assemble with z80asm (GNU):  z80asm -o pv-1000_control_test.bin src/control-test.asm
; (or just `make`). Z80 CPU at 3.58 MHz; no BIOS: the cartridge starts at address 0.
;
; Hardware used (see https://obscure.nesdev.org/wiki/Casio_PV-1000):
;   0x0000-0x3FFF  cartridge ROM; tile patterns are read from here too (tile N at N*32)
;   0xB800-0xBBFF  RAM: tile map (32 x 24, from 0xB800) and work RAM
;   port 0xF8-0xFA sound channels 1-3 (frequency = 8739 Hz / (63 - n); 63 = silent)
;   port 0xFB      sound control: bit 1 = sound on (off at power-on)
;   port 0xFC      write: bit 0 enables the frame interrupt; read: bit 0 = a new frame started
;   port 0xFD      joystick matrix: write the row (1, 2, 4, 8), then read its buttons
;   port 0xFF      bits 7-5 = tile pattern bank, the rest = border color (0 = black)

MAP:    equ 0xB800          ; tile map, 32 x 24
ROWS:   equ 0xBB00          ; the 4 matrix rows read this frame
ANY:    equ 0xBB10          ; bit 0: something held on controller 1, bit 1: on controller 2
FRAMES: equ 0xBB11          ; frame counter, shown in the title
NEW_FRAME: equ 0xBB12       ; set by the interrupt when a new frame starts

; ------------------------------------------------------------------ header (power-on)
        org 0x0000
        di
        ld sp,0xBC00        ; the stack grows down from 0xBBFF, below the RAM tile patterns
                            ; (0xBC00-0xBFFF), so it never overwrites them
        jp start

; ------------------------------------------------------------------ interrupt (IM 1)
; The frame is waited for with the interrupt, as the games do, and not by polling port
; 0xFC: the MiSTer core clears its flag on the read, and loses a frame when the flag is set
; in the same clock as the read. Here port 0xFC is read only in the interrupt, long after
; the flag is set. The MiSTer core interrupts on several lines per frame; only the one with
; bit 0 of port 0xFC set is the new frame, and it returns with interrupts off: on the real
; console it stays pending until port 0xFD is written, which the matrix read right after
; does. The wait enables them again. 0x0038 is in tile 0x01, which is left unused for this.
        ds 0x0038-$
        jp irq

; ------------------------------------------------------------------ fonts
        ds 0x0040-$
        include "font-yellow.asm"   ; tiles 0x02-0x16: yellow on black (the credit line)
        ds 0x0400-$
        include "font.asm"          ; tiles 0x20-0xDF: white, title and lit

; ------------------------------------------------------------------ program
        ds 0x1C00-$
start:
        ld a,0
        out (0xFF),a        ; black border, tile patterns bank 0
        ld a,63
        out (0xF8),a        ; the three sound channels silent
        out (0xF9),a
        out (0xFA),a
        ld a,0x02
        out (0xFB),a        ; sound on (it starts off, as on the real console)
        ld a,0x01
        out (0xFC),a        ; enable the "new frame" flag and interrupt (bit 0 of port 0xFC).
                            ; The MiSTer core sets the flag even without this; the real
                            ; console and MAME don't

        ld hl,MAP           ; clear the map with spaces
        ld (hl),0x20
        ld de,MAP+1
        ld bc,32*24-1
        ldir

        ld hl,texts         ; static texts: (address, string, 0)... ; address 0 = end
text:   ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or e
        jr z,ready
chr:    ld a,(hl)
        inc hl
        or a
        jr z,text
        ld (de),a
        inc de
        jr chr

ready:  xor a
        ld (NEW_FRAME),a
        im 1

main:   ei
        halt                ; wait for a new frame
        ld a,(NEW_FRAME)
        or a
        jr z,main
        xor a
        ld (NEW_FRAME),a

        ld hl,FRAMES        ; the frame counter, after the matrix rows: if it stops, the
        inc (hl)            ; program is stuck (it no longer sees new frames)
        ld a,(hl)
        ld de,MAP+20*32+25
        ld c,0              ; plain white tiles
        call hex2

        ld a,1              ; read the 4 matrix rows; after selecting each row, wait
        out (0xFD),a        ; for the wiring to settle (see `settle`)
        call settle
        in a,(0xFD)
        ld (ROWS+0),a
        ld a,2
        out (0xFD),a
        call settle
        in a,(0xFD)
        ld (ROWS+1),a
        ld a,4
        out (0xFD),a
        call settle
        in a,(0xFD)
        ld (ROWS+2),a
        ld a,8
        out (0xFD),a
        call settle
        in a,(0xFD)
        ld (ROWS+3),a

        xor a
        ld (ANY),a
        ld hl,items         ; each label: matrix row, mask, map address, length
item:   ld a,(hl)
        cp 0xFF
        jr z,sound
        ld e,a              ; DE = ROWS + row
        ld d,ROWS/256
        ld a,(de)
        inc hl
        ld b,(hl)           ; this button's bit
        inc hl
        and b
        ld c,0
        jr z,off
        ld c,0x80           ; held: lit tiles (bit 7) and a beep for its controller
        ld a,b
        and 0x0C            ; bits 2-3 = controller 2
        ld a,1
        jr z,player
        ld a,2
player: ld b,a
        ld a,(ANY)
        or b
        ld (ANY),a
off:    ld e,(hl)           ; DE = where the label is, B = its length
        inc hl
        ld d,(hl)
        inc hl
        ld b,(hl)
        inc hl
paint:  ld a,(de)           ; bit 7 of each tile = lit
        and 0x7F
        or c
        ld (de),a
        inc de
        djnz paint
        jr item

sound:  ld a,(ANY)          ; a beep per controller: 1 on channel 1 (n = 40, about 380 Hz),
        ld b,a              ; 2 on channel 2 (n = 48, about 580 Hz)
        rrca
        ld a,63
        jr nc,mute1
        ld a,40
mute1:  out (0xF8),a
        ld a,b
        and 2
        ld a,63
        jr z,mute2
        ld a,48
mute2:  out (0xF9),a

        ld hl,ROWS          ; the raw rows, the whole byte in hexadecimal, at row 20,
        ld de,MAP+20*32+8   ; columns 8, 11, 14 and 17
        ld c,0              ; plain white tiles
        ld b,4
rows:   ld a,(hl)
        call hex2
        inc de
        inc hl
        djnz rows
        jp main

; The interrupt: marks a new frame when bit 0 of port 0xFC is set (see the vector at 0x0038).
irq:    push af
        in a,(0xFC)
        and 1
        jr z,irq_other
        ld (NEW_FRAME),a    ; a new frame: back with interrupts off
        pop af
        reti
irq_other:
        pop af
        ei
        reti

; Writes A as two hexadecimal digits at DE (DE ends after them). C is added to each
; ASCII code: 0 for white tiles.
hex2:   push af
        rrca
        rrca
        rrca
        rrca
        call hex1
        pop af
hex1:   and 0x0F
        cp 10
        jr c,digit
        add a,7
digit:  add a,0x30
        add a,c
        ld (de),a
        inc de
        ret

; Waits about 180 T-states. On the real console a press takes up to 41 T-states to show
; after its row is selected, and up to 147 to go away after the row is deselected
; (NESdev Wiki, Casio PV-1000/Controller); reading at once could miss presses or show the
; previous row's. Emulators read instantly, so there it makes no difference.
settle: ld b,12             ; 12 x 13 T-states (djnz) + call/ld/ret
settle_loop:
        djnz settle_loop
        ret

; ------------------------------------------------------------------ data
; texts: map address (row * 32 + column), then the string ending in 0
texts:
        dw MAP+0*32+0           ; the title: white on a blue bar across the whole row
        db 0x60,0x60,0x60,0x60,0x60,0x60,0x90,0x96,0x6D,0x71,0x70,0x70,0x70,0x60,0x83,0x8F,0x8E,0x94,0x92,0x8F,0x8C,0x60,0x94,0x85,0x93,0x94,0x60,0x60,0x60,0x60,0x60,0x60,0
                                ; (tiles 0x60-0x9F = ASCII + 0x40: "      PV-1000 CONTROL TEST      ")
        dw MAP+2*32+4
        db "PLAYER 1",0
        dw MAP+2*32+18
        db "PLAYER 2",0
        dw MAP+20*32+4
        db "MTX",0              ; the matrix rows
        dw MAP+20*32+21
        db "FRM",0              ; the frame counter
        dw MAP+23*32+6
        db 0x0E,0x16,0x02,0x13,0x10,0x14,0x11,0x0F,0x12,0x10,0x15,0x02,0x15,0x03,0x02,0x06,0x04,0x06,0x0A,0
                                ; "BY PERICLES S. 2026" in yellow (codes from tools/font.py --yellow)
        dw MAP+4*32+3
        db " UP      ",0
        dw MAP+4*32+17
        db " UP      ",0
        dw MAP+6*32+3
        db " DOWN    ",0
        dw MAP+6*32+17
        db " DOWN    ",0
        dw MAP+8*32+3
        db " LEFT    ",0
        dw MAP+8*32+17
        db " LEFT    ",0
        dw MAP+10*32+3
        db " RIGHT   ",0
        dw MAP+10*32+17
        db " RIGHT   ",0
        dw MAP+12*32+3
        db " FIRE 1  ",0
        dw MAP+12*32+17
        db " FIRE 1  ",0
        dw MAP+14*32+3
        db " FIRE 2  ",0
        dw MAP+14*32+17
        db " FIRE 2  ",0
        dw MAP+16*32+3
        db " SELECT  ",0
        dw MAP+16*32+17
        db " SELECT  ",0
        dw MAP+18*32+3
        db " START   ",0
        dw MAP+18*32+17
        db " START   ",0
        dw 0

; items: matrix row, button mask, label address, label length (9 tiles).
; Player 1 uses bits 0-1 of each row, player 2 bits 2-3.
;   row 0: Select, Start    row 1: Down, Right    row 2: Left, Up    row 3: Fire 2, Fire 1
items:
        db 2,0x02
        dw MAP+4*32+3
        db 9                ; P1 up
        db 2,0x08
        dw MAP+4*32+17
        db 9                ; P2 up
        db 1,0x01
        dw MAP+6*32+3
        db 9                ; P1 down
        db 1,0x04
        dw MAP+6*32+17
        db 9                ; P2 down
        db 2,0x01
        dw MAP+8*32+3
        db 9                ; P1 left
        db 2,0x04
        dw MAP+8*32+17
        db 9                ; P2 left
        db 1,0x02
        dw MAP+10*32+3
        db 9                ; P1 right
        db 1,0x08
        dw MAP+10*32+17
        db 9                ; P2 right
        db 3,0x02
        dw MAP+12*32+3
        db 9                ; P1 fire 1
        db 3,0x08
        dw MAP+12*32+17
        db 9                ; P2 fire 1
        db 3,0x01
        dw MAP+14*32+3
        db 9                ; P1 fire 2
        db 3,0x04
        dw MAP+14*32+17
        db 9                ; P2 fire 2
        db 0,0x01
        dw MAP+16*32+3
        db 9                ; P1 select
        db 0,0x04
        dw MAP+16*32+17
        db 9                ; P2 select
        db 0,0x02
        dw MAP+18*32+3
        db 9                ; P1 start
        db 0,0x08
        dw MAP+18*32+17
        db 9                ; P2 start
        db 0xFF

; ------------------------------------------------------------------ padding to 8 KB
        ds 0x2000-$
