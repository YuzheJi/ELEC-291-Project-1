; 76E003 ADC test program: Reads channel 7 on P1.1, pin 14

$NOLIST
$MODN76E003
$LIST



;  N76E003 pinout:
;                               -------

;       PWM2/IC6/T0/AIN4/P0.5 -|1    20|- P0.4/AIN5/STADC/PWM3/IC3
;               TXD/AIN3/P0.6 -|2    19|- P0.3/PWM5/IC5/AIN6
;               RXD/AIN2/P0.7 -|3    18|- P0.2/ICPCK/OCDCK/RXD_1/[SCL]
;                    RST/P2.0 -|4    17|- P0.1/PWM4/IC4/MISO
;        INT0/OSCIN/AIN1/P3.0 -|5    16|- P0.0/PWM3/IC3/MOSI/T1
;              INT1/AIN0/P1.7 -|6    15|- P1.0/PWM2/IC2/SPCLK
;                         GND -|7    14|- P1.1/PWM1/IC1/AIN7/CLO
;[SDA]/TXD_1/ICPDA/OCDDA/P1.6 -|8    13|- P1.2/PWM0/IC0
;                         VDD -|9    12|- P1.3/SCL/[STADC]
;            PWM5/IC7/SS/P1.5 -|10   11|- P1.4/SDA/FB/PWM1
;                               -------
;

CLK               EQU 16600000 ; Microcontroller system frequency in Hz
BAUD              EQU 115200 ; Baud rate of UART in bps
TIMER1_RELOAD     EQU (0x100-(CLK/(16*BAUD)))
TIMER0_RELOAD_1MS EQU (0x10000-(CLK/1000))
TIMER2_RATE   	  EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER2_RELOAD 	  EQU ((65536-(CLK/TIMER2_RATE)))

SOUND_OUT 		  EQU P1.5
MENU			  EQU P3.0
SELECT            EQU p1.6

; Reset vector
org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	reti

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	ljmp Serial_ISR
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

;                       123456789012345    <- This helps determine the location of the counter
test_message:     	db 'Temp:    xx.xxxC', 0
voltage_message:    db 'V(pin 14)=      ', 0
line_animation:		db 'C              H'
cseg
; These 'equ' must match the hardware wiring
LCD_RS equ P1.3
;LCD_RW equ PX.X ; Not used in this code, connect the pin to GND
LCD_E  equ P1.4
LCD_D4 equ P0.0
LCD_D5 equ P0.1
LCD_D6 equ P0.2
LCD_D7 equ P0.3

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

; These register definitions needed by 'math32.inc'
DSEG at 30H
receive_count:  ds 1
x:   			ds 4
y:   			ds 4
hex_voltage:	ds 4
bcd: 			ds 5

; This is for the threshold warning
bcd_temp_threshold: ds 5

; Here are for future features
bcd_temp_max:	ds 5
bcd_temp_min:	ds 5
bcd_temp_swap:	ds 5


BSEG
mf: dbit 1

$NOLIST
$include(math32.inc)
$LIST

Timer2_ISR:
	clr TF2  
	cpl P0.4
	cpl SOUND_OUT 
	reti

Serial_ISR:
	reti

Init_All:
	; Configure all the pins for biderectional I/O
	mov	P3M1, #0x00
	mov	P3M2, #0x00
	mov	P1M1, #0x00
	mov	P1M2, #0x00
	mov	P0M1, #0x00
	mov	P0M2, #0x00
	
	orl	CKCON, #0x10 ; CLK is the input for timer 1
	orl	PCON, #0x80 ; Bit SMOD=1, double baud rate
	mov	SCON, #0x52
	anl	T3CON, #0b11011111
	anl	TMOD, #0x0F ; Clear the configuration bits for timer 1
	orl	TMOD, #0x20 ; Timer 1 Mode 2
	mov	TH1, #TIMER1_RELOAD ; TH1=TIMER1_RELOAD;
	setb TR1

	mov T2CON, #0 						; Stop timer/counter.  Autoreload mode.
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)
	orl T2MOD, #0x80 					; Enable timer 2 autoreload
	mov RCMP2H, #high(TIMER2_RELOAD)
	mov RCMP2L, #low(TIMER2_RELOAD)
	orl EIE, #0x80 						; Enable timer 2 interrupt ET2=1
    
	
	; Using timer 0 for delay functions.  Initialize here:
	clr	TR0 ; Stop timer 0
	orl	CKCON,#0x08 ; CLK is the input for timer 0
	anl	TMOD,#0xF0 ; Clear the configuration bits for timer 0
	orl	TMOD,#0x01 ; Timer 0 in Mode 1: 16-bit timer
	
	; Initialize the pin used by the ADC (P1.1) as input.
	orl	P1M1, #0b00000010
	anl	P1M2, #0b11111101
	
	; Initialize and start the ADC:
	anl ADCCON0, #0xF0 ;
	orl ADCCON0, #0x07 ; Select channel 7
	; AINDIDS select if some pins are analog inputs or digital I/O:
	mov AINDIDS, #0x00 ; Disable all analog inputs
	orl AINDIDS, #0b10000000 ; P1.1 is analog input
	orl ADCCON1, #0x01 ; Enable ADC
	
	mov a, #0x00
	mov receive_count, a
	ret
	
wait_1ms:
	clr	TR0 ; Stop timer 0
	clr	TF0 ; Clear overflow flag
	mov	TH0, #high(TIMER0_RELOAD_1MS)
	mov	TL0,#low(TIMER0_RELOAD_1MS)
	setb TR0
	jnb	TF0, $ ; Wait for overflow
	ret

; Wait the number of miliseconds in R2
waitms:
	lcall wait_1ms
	djnz R2, waitms
	ret

; We can display a number any way we want.  In this case with
; four decimal places.
Display_formated_BCD_voltage:
	Set_Cursor(2, 10)
	Display_BCD(bcd+2)
	Display_char(#'.')
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	Set_Cursor(2, 10)
	Display_char(#'=')
	ret

Display_formated_BCD_temp:
	Set_Cursor(1, 10)
	Display_BCD(bcd+2)
	Display_char(#'.')
	Display_BCD(bcd+1)
	ret

Display_formated_BCD_temp_th:
	Set_Cursor(1, 10)
	Display_BCD(bcd_temp_threshold+2)
	Display_char(#'.')
	Display_BCD(bcd_temp_threshold+1)
	ret

Display_formated_BCD_temp_MM:
	Set_Cursor(1, 10)
	Display_BCD(bcd_temp_max+2)
	Display_char(#'.')
	Display_BCD(bcd_temp_max+1)
	Set_Cursor(2, 10)
	Display_BCD(bcd_temp_min+2)
	Display_char(#'.')
	Display_BCD(bcd_temp_min+1)
	ret

main:
	mov sp, #0x7f
	lcall Init_All
    lcall LCD_4BIT
	setb EA

	clr a
	mov bcd_temp_threshold+0, a
	mov bcd_temp_threshold+1, a
	mov bcd_temp_threshold+3, a
	mov bcd_temp_threshold+4, a
	mov a, #0x27
	mov bcd_temp_threshold+2, a

	clr a 
	mov bcd_temp_max+0, a
	mov bcd_temp_max+1, a
	mov bcd_temp_max+2, a
	mov bcd_temp_max+3, a
	mov bcd_temp_max+4, a

	mov a, #0x00
	mov bcd_temp_min+0, a
	mov bcd_temp_min+3, a
	mov bcd_temp_min+4, a
	mov a, #0x99
	mov bcd_temp_min+2, a
	mov bcd_temp_min+1, a

	lcall open_animation
	lcall Mychar

main_page:
    ; initial messages in LCD
	Set_Cursor(1, 1)
    Send_Constant_String(#test_message)
	Set_Cursor(2, 1)
    Send_Constant_String(#line_animation)
	Set_Cursor(1, 15)
	WriteData(#0b0000_0010)

	clr P1.7
	
Forever:
	clr ADCF
	setb ADCS ;  ADC start trigger signal
    jnb ADCF, $ ; Wait for conversion complete

	jb MENU, MENU_not_pressed
	mov R2, #0d10
	lcall waitms 
	jb MENU, MENU_not_pressed
	jnb MENU, $
	ljmp MENU_page1

MENU_not_pressed:
    ; Read the ADC result and store in [R1, R0] R1 high 4 R0 low
    mov a, ADCRH   
    swap a
    push acc
    anl a, #0x0f
    mov R1, a
    pop acc
    anl a, #0xf0
    orl a, ADCRL
    mov R0, A
    
    ; Convert to voltage
	mov x+0, R0
	mov x+1, R1
	mov x+2, #0
	mov x+3, #0
	Load_y(51640) ; VCC voltage measured
	lcall mul32
	Load_y(4095) ; 2^12-1
	lcall div32

	lcall Storehex_voltage
		
	; now voltage is x
	; Convert to BCD and display
	lcall voltage2temp

	; convert temp into BCD
	lcall hex2bcd
	lcall Display_formated_BCD_temp

	lcall Compare_print
	lcall Compare_warning
	lcall Compare_record
	; convert temp into ASCII, send to serial
	lcall bcd2ASCII
	
	; Wait 500 ms between conversions
	mov R2, #250
	lcall waitms
	mov R2, #250
	lcall waitms

	ljmp Forever
	
; menu page 1 loop
MENU_page1:
	Set_Cursor(1,1)
	Send_Constant_String(#MENU_page_string_line1)
	Set_Cursor(2,1)
	Send_Constant_String(#MENU_page_string_line2)
	Set_Cursor(1,15)
	Send_Constant_String(#Arrow)

MENU_page1_loop:
	jb MENU, MENU_page1_MENU_not_pressed
	mov R2, #0d10
	lcall waitms 
	jb MENU, MENU_page1_MENU_not_pressed
	jnb MENU, $
	ljmp MENU_page2

MENU_page1_MENU_not_pressed:
	jb SELECT, MENU_page1_SELECT_not_pressed
	mov R2, #0d10
	jb SELECT, MENU_page1_SELECT_not_pressed
	jnb SELECT, $
	ljmp Alert_page

MENU_page1_SELECT_not_pressed:
	ljmp MENU_page1_loop

; menu page 2 loop
MENU_page2:
	Set_Cursor(1,1)
	Send_Constant_String(#MENU_page_string_line1)
	Set_Cursor(2,1)
	Send_Constant_String(#MENU_page_string_line2)
	Set_Cursor(2,15)
	Send_Constant_String(#Arrow)

MENU_page2_loop:
	jb MENU, MENU_page2_MENU_not_pressed
	mov R2, #0d10
	lcall waitms 
	jb MENU, MENU_page2_MENU_not_pressed
	jnb MENU, $
	ljmp main_page

MENU_page2_MENU_not_pressed:
	jb SELECT, MENU_page2_SELECT_not_pressed
	mov R2, #0d10
	jb SELECT, MENU_page2_SELECT_not_pressed
	jnb SELECT, $
	ljmp Statistics_page

MENU_page2_SELECT_not_pressed:
	ljmp MENU_page2_loop

Alert_page:
	Set_Cursor(1,1)
	Send_Constant_String(#Alert_string)
	Set_Cursor(1, 15)
	WriteData(#0b0000_0010)
	Set_Cursor(2,1)
	Send_Constant_String(#clr_row)

Alert_page_loop:
	jb MENU, Alert_page_MENU_not_pressed
	mov R2, #0d10
	lcall waitms 
	jb MENU, Alert_page_MENU_not_pressed
	jnb MENU, $
	ljmp MENU_page1

Alert_page_MENU_not_pressed:
	lcall Display_formated_BCD_temp_th
	ljmp Alert_page_loop

Statistics_page:
	Set_Cursor(1,1)
	Send_Constant_String(#Max_string)
	Set_Cursor(1, 15)
	WriteData(#0b0000_0010)
	Set_Cursor(2,1)
	Send_Constant_String(#Min_string)
	Set_Cursor(2, 15)
	WriteData(#0b0000_0010)

Statistics_page_loop:
	jb MENU, Statistics_page_MENU_not_pressed
	mov R2, #0d10
	lcall waitms 
	jb MENU, Statistics_page_MENU_not_pressed
	jnb MENU, $
	ljmp MENU_page1

Statistics_page_MENU_not_pressed:
	lcall Display_formated_BCD_temp_MM
	ljmp Statistics_page_loop

; below are somefunctions

; put a char to the serial
putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
    ret

; write a constant string at one time
SendString:
    clr A
    movc A, @A+DPTR
    jz SendStringDone
    lcall putchar
    inc DPTR
    sjmp SendString
SendStringDone:
    ret

; store hex_voltage from x to ram(hex_voltage)
Storehex_voltage:
	mov a, x+0
	mov hex_voltage+0, a
	mov a, x+1
	mov hex_voltage+1, a
	mov a, x+2
	mov hex_voltage+2, a
	mov a, x+3
	mov hex_voltage+3, a
	ret

; load hex_voltage from ram to x(hex_voltage)
loadhex_voltage:
	mov a, hex_voltage+0
	mov x+0, a
	mov a, hex_voltage+1
	mov x+1, a
	mov a, hex_voltage+2
	mov x+2, a
	mov a, hex_voltage+3
	mov x+3, a
	ret

; this requires x to be the ADC voltage
voltage2temp:
	Load_y(27300)
	lcall sub32
	Load_y(100)
	lcall mul32
	ret	

; get bcd into ASCII and send to serial
bcd2ASCII:

	mov a, bcd+3
	anl a, #0b1111_0000
	swap a
	add a, #0d48
	lcall putchar

	mov a, bcd+3
	anl a, #0b0000_1111
	add a, #0d48
	lcall putchar

	mov a, bcd+2
	anl a, #0b1111_0000
	swap a
	add a, #0d48
	lcall putchar

	mov a, bcd+2
	anl a, #0b0000_1111
	add a, #0d48
	lcall putchar

	mov a, bcd+1
	anl a, #0b1111_0000
	swap a
	add a, #0d48
	lcall putchar

	mov a, bcd+1
	anl a, #0b0000_1111
	add a, #0d48
	lcall putchar
	mov a, #'\n'
	lcall putchar
	ret

open_animation:

	Set_Cursor(1,2)
	Display_char(#'E')
	mov R2, #90
	lcall waitms
	Display_char(#'L')
	mov R2, #90
	lcall waitms
	Display_char(#'E')
	mov R2, #90
	lcall waitms
	Display_char(#'C')
	mov R2, #90
	lcall waitms
	Display_char(#'2')
	mov R2, #90
	lcall waitms
	Display_char(#'9')
	mov R2, #90
	lcall waitms
	Display_char(#'1')
	mov R2, #90
	lcall waitms
	Display_char(#'-')
	mov R2, #90
	lcall waitms
	Display_char(#'L')
	mov R2, #90
	lcall waitms
	Display_char(#'a')
	mov R2, #90
	lcall waitms
	Display_char(#'b')
	mov R2, #90
	lcall waitms
	Display_char(#'3')

	Set_Cursor(2,4)
	Display_char(#'T')
	mov R2, #90
	lcall waitms
	Display_char(#'h')
	mov R2, #90
	lcall waitms
	Display_char(#'e')
	mov R2, #90
	lcall waitms
	Display_char(#'r')
	mov R2, #90
	lcall waitms
	Display_char(#'m')
	mov R2, #90
	lcall waitms
	Display_char(#'o')
	mov R2, #90
	lcall waitms
	Display_char(#'m')
	mov R2, #90
	lcall waitms
	Display_char(#'e')
	mov R2, #90
	lcall waitms
	Display_char(#'t')
	mov R2, #90
	lcall waitms
	Display_char(#'e')
	mov R2, #90
	lcall waitms
	Display_char(#'r')

	mov R2, #250
	lcall waitms
	mov R2, #250
	lcall waitms
	mov R2, #250
	lcall waitms
	mov R2, #250
	lcall waitms
	mov R2, #250
	lcall waitms
	mov R2, #250
	lcall waitms
	mov R2, #250
	lcall waitms
	mov R2, #250
	lcall waitms
	ret

Mychar:
	; 0000_*000
	WriteCommand(#0x40)
	WriteData(#0b1111_1111)
	WriteData(#0b1111_1111)
	WriteData(#0b1111_1111)
	WriteData(#0b1111_1111)
	WriteData(#0b1111_1111)
	WriteData(#0b1111_1111)
	WriteData(#0b1111_1111)
	WriteData(#0b0000_0000)

	WriteCommand(#0x50)
	WriteData(#0b111_00000)
	WriteData(#0b111_00011)
	WriteData(#0b111_00011)
	WriteData(#0b111_00000)
	WriteData(#0b111_00000)
	WriteData(#0b111_00000)
	WriteData(#0b111_00000)
	WriteData(#0b000_00000)
	ret

; This func controls the strip on 2nd row
Compare_print:
	
	push acc
	push aR0

	Set_Cursor(2,2)
	; put MS2B into a
	mov a, bcd+2
	anl a, #0b1111_0000 ; get high 4 -> 1st BCD digit
	swap a
	add a, #0d05
	mov R0, a
	push acc
Check_a_for_block:
	djnz R0, Draw_block
	pop acc
	mov R0, a
	mov a, #0d16
	clr cy
	subb a, R0
	mov R0, a
Check_a_for_space:
	djnz R0, Draw_space
	pop aR0
	pop acc
	ret

Draw_block:
	WriteData(#0x00)
	sjmp Check_a_for_block
Draw_space:	
	WriteData(#' ')
	sjmp Check_a_for_space

Compare_warning:

	push acc
	push aR0

check_1st_digi:

	mov a, bcd+2
	swap a 
	anl a, #0b0000_1111
	mov R0, a ; R0 has a high 4-> 1st dig
	mov a, bcd_temp_threshold+2
	swap a 
	anl a, #0b0000_1111
	clr cy 
	subb a, R0 ; a= thr.1 - temp.1
	jb CY, warning 
	jz check_2nd_digi
	jnb CY, safe

check_2nd_digi:

	mov a, bcd+2 
	anl a, #0b0000_1111
	mov R0, a ; R0 has a low 4-> 2st digi
	mov a, bcd_temp_threshold+2
	anl a, #0b0000_1111
	clr cy 
	subb a, R0 ; a= thr.2 - temp.2
	jb CY, warning 
	jz warning
	jnb CY, safe

safe:
	clr P1.7
	clr TR2
	pop aR0
	pop acc 
	ret

warning:
	setb P1.7
	setb TR2 
	pop aR0
	pop acc 
	ret

Compare_record:
	push acc
	push aR0

Compare_record_MAX:
	mov a, bcd+2
	mov R0, bcd_temp_max+2
	clr Cy 
	subb a, R0 
	jnb Cy, update_max_head
	jz Compare_record_MAX_2nd
	sjmp Compare_record_MIN

Compare_record_MAX_2nd:
	mov a, bcd+1
	mov R0, bcd_temp_max+1
	clr Cy 
	subb a, R0 
	jnb Cy, update_max_head

Compare_record_MIN:
	mov a, bcd_temp_min+2
	mov R0, bcd+2
	clr Cy 
	subb a, R0 
	jnb Cy, update_min_head
	jz Compare_record_MIN_2nd
	sjmp Compare_record_exit

Compare_record_MIN_2nd:
	mov a, bcd_temp_min+1
	mov R0, bcd+1
	clr Cy 
	subb a, R0 
	jnb Cy, update_min_head

Compare_record_exit:
	pop aR0	
	pop acc
	ret

update_max_head:
	mov a, bcd+0
	mov bcd_temp_max+0,a
	mov a, bcd+1
	mov bcd_temp_max+1,a
	mov a, bcd+2
	mov bcd_temp_max+2,a
	mov a, bcd+3
	mov bcd_temp_max+3,a
	mov a, bcd+4
	mov bcd_temp_max+4,a
	ljmp Compare_record_exit

update_min_head:
	mov a, bcd+0
	mov bcd_temp_min+0,a
	mov a, bcd+1
	mov bcd_temp_min+1,a
	mov a, bcd+2
	mov bcd_temp_min+2,a
	mov a, bcd+3
	mov bcd_temp_min+3,a
	mov a, bcd+4
	mov bcd_temp_min+4,a
	ljmp Compare_record_exit

Temp_max_to_y:
	push acc
	; copy bcd to swap
	mov a, bcd+0
	mov bcd_temp_swap+0,a
	mov a, bcd+1
	mov bcd_temp_swap+1,a
	mov a, bcd+2
	mov bcd_temp_swap+2,a
	mov a, bcd+3
	mov bcd_temp_swap+3,a
	mov a, bcd+4
	mov bcd_temp_swap+4,a

	; copy bcd_max to bcd
	mov a, bcd_temp_max+0
	mov bcd+0,a
	mov a, bcd_temp_max+1
	mov bcd+1,a
	mov a, bcd_temp_max+2
	mov bcd+2,a
	mov a, bcd_temp_max+3
	mov bcd+3,a
	mov a, bcd_temp_max+4
	mov bcd+4,a

	; convert to hex in x
	lcall bcd2hex 
	load_y(x) 

	; copy bcd back from swap
	mov a, bcd_temp_swap+0
	mov bcd+0,a
	mov a, bcd_temp_swap+1
	mov bcd+1,a
	mov a, bcd_temp_swap+2
	mov bcd+2,a
	mov a, bcd_temp_swap+3
	mov bcd+3,a
	mov a, bcd_temp_swap+4
	mov bcd+4,a

	pop acc 
	ret

Temp_min_to_y:
	push acc
	; copy bcd to swap
	mov a, bcd+0
	mov bcd_temp_swap+0,a
	mov a, bcd+1
	mov bcd_temp_swap+1,a
	mov a, bcd+2
	mov bcd_temp_swap+2,a
	mov a, bcd+3
	mov bcd_temp_swap+3,a
	mov a, bcd+4
	mov bcd_temp_swap+4,a

	; copy bcd_min to bcd
	mov a, bcd_temp_min+0
	mov bcd+0,a
	mov a, bcd_temp_min+1
	mov bcd+1,a
	mov a, bcd_temp_min+2
	mov bcd+2,a
	mov a, bcd_temp_min+3
	mov bcd+3,a
	mov a, bcd_temp_min+4
	mov bcd+4,a

	; convert to hex in x
	lcall bcd2hex 
	load_y(x) 

	; copy bcd back from swap
	mov a, bcd_temp_swap+0
	mov bcd+0,a
	mov a, bcd_temp_swap+1
	mov bcd+1,a
	mov a, bcd_temp_swap+2
	mov bcd+2,a
	mov a, bcd_temp_swap+3
	mov bcd+3,a
	mov a, bcd_temp_swap+4
	mov bcd+4,a

	pop acc 
	ret

clr_row:
	;	0123456789012345
	DB '                ', 0
MENU_page_string_line1:
	;	0123456789012345
	DB '1.Alert temp    ', 0
MENU_page_string_line2:
	;	0123456789012345
	DB '2.Statistics    ', 0
Arrow:
	DB '<-',0
Alert_string:
	;	0123456789012345
	DB 'Alert:   xx.xxxC', 0
Max_string:
	;	0123456789012345
	DB 'MAX:     xx.xxxC', 0
Min_string:
	;	0123456789012345
	DB 'MIN:     xx.xxxC', 0
Debug_message:
    DB  'Hello, World!  ', 0
END
	
	