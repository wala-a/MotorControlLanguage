; address definitions
.equ PORT_A_ADDR, 0FE20h
.equ PORT_B_ADDR, 0fe21h
.equ PORT_C_ADDR, 0fe22h
.equ CTRL_WRD_ADDR, 0fe23h
; data definitions for directional motor control
; in the format: MOTOR_DIRECTION_8255PORT
.equ MOTOR0_POS_C, 	 00000100b
.equ MOTOR0_NEG_C, 	 00001000b
.equ MOTOR1_POS_B, 00000001b
.equ MOTOR1_NEG_B, 10000000b
.equ MOTOR2_POS_B, 	 01000000b
.equ MOTOR2_NEG_B, 	 00100000b
.equ MOTOR3_POS_B, 	 00001000b
.equ MOTOR3_NEG_B, 	 00010000b
.equ MOTOR4_POS_B,  00000010b
.equ MOTOR4_NEG_B,  00000100b

;registers to hold the values to write to each port of 8255
.equ PORT_B_WRITE_DATA, 03h
.equ PORT_C_WRITE_DATA, 02h
; register names to hold the high and low counts of the duty cycle
.EQU HIGH_COUNT, 01h
.EQU LOW_COUNT,  00h
; registers to hold values for the high and low counts of the 
; duty cycle this is determined by the desired duty cycle
.EQU RHIGH, 05h
.EQU RLOW, 06h
; RHIGH + RLOW = 100d
;register to hold the status of the pwm count: hi/lo
.equ STATUS, 07h
.equ HI, 0FFh
.equ LO, 00h
;SETTINGS:
.equ POS_CTRL_UNAVAILABLE, 0ffh
.equ SPD_CTRL_UNAVAILABLE, 000b

.org 000h
ljmp start

; timer interrupts to handle the PWM
.org 00Bh
T0ISR:
	; check the STATUS register (R7) and jmp accordingly
	cjne R7, #LO, lowct
	;load the reload value for the next timer expiration
	;if cpl(A) is high, the next round will be low, and vice versa
	highct:	
		mov TH0, HIGH_COUNT		; set the count to the high value
		mov STATUS, #HI			; set the status to HI
		;setb p3.5
		reti
	lowct:
		mov TH0, LOW_COUNT		; set the count to the low value
		mov STATUS, #LO			; set the status to LO
		;clr p3.5
		reti

; Serial interrupt to handle incoming data from PSoC
.org 0023h
SerialISR:
	;check the transmit flag
	;jb ti, return				;if the interrupt was caused by a transmit, just reti
	lcall getchr
	mov p1, a					;debugging
	;lcall sndchr				;debugging
	; interpret the different sections of a (PSoC communication)
	lcall parsePSoCInput
	return:
		reti


start:
	lcall initSerial
	lcall setup8255
	mov RHIGH, #50d			;initialize pwm to 50% duty cycle
	lcall pwmSetup
	lcall timersetup

	loop: ljmp loop
	

;setup the timer to produce PWM via interrupts
timersetup:
	setb tr0				;enable timer 0 (tcon)
	;mov tmod, #00000010b	;timer 0 autoreload mode
	;mov IE, #82h		  	;enable interrupts
	ret

;setup the 8255 control word
setup8255:
	mov dptr, #CTRL_WRD_ADDR
	mov a, #90h
	movx @dptr, a			; init the control word of the 8255 so that all ports
							; are output ports
	mov dptr, #PORT_C_ADDR	; move the address in dptr to output data to port C
	mov a, #00h
	movx @dptr, a			; zero out port c
	mov dptr, #PORT_B_ADDR	; move the address in dptr to output data to port b
	movx @dptr, a			; zero out port b
	ret

;=================================================================
; subroutine pwmSetup
; this routine to be called when pwm needs to be setup or re-setup
; to set different duty cycles
;=================================================================
pwmSetup:
	;insert value into high count and low count registers
	mov a, #255d		;subtract the count value from 255 because the 8051
	subb a, RHIGH		;timer counts UP from the value to 255	
	mov HIGH_COUNT, a
	
	mov a, #100d
	subb a, RHIGH		;subtract rhigh from 100 in order to get the low count
	mov RLOW, a			; since RLOW + RHIGH = 100 always
	
	mov a, #255d		;subtract the count value from 255 because the 8051
	subb a, RLOW		;timer counts UP from the value to 255	
	mov LOW_COUNT, a
	
	;setup the square wave status (init at low)
	mov TH0, LOW_COUNT		; initialize the value of timer 0 with low count
	mov STATUS, #LO			; initialize the status to LO
	ret
	
;=================================================================
; subroutine initSerial
; this routine initializes the hardware
; set up serial port with a 11.0592 MHz crystal,
; use timer 1 for 9600 baud serial communications
;=================================================================
initSerial:
   mov   ie,   #92h		  ; enable all interrupts and serial interrupt and timer 0
   mov   tmod, #22h       ; set timer 1 and timer 2 (for pwm) for auto reload - mode 2
   mov   tcon, #41h       ; run counter 1 and set edge trig ints
   mov   th1,  #0fdh      ; set 9600 baud with xtal=11.059mhz
   mov   scon, #50h       ; set serial control reg for 8 bit data
                          ; and mode 1
   ret
;===============================================================
; subroutine sndchr
; this routine takes the chr in the acc and sends it out the
; serial port.
;===============================================================
sndchr:
   clr  scon.1            ; clear the tx  buffer full flag.
   mov  sbuf,a            ; put chr in sbuf
txloop:
   jnb  scon.1, txloop    ; wait till chr is sent
   ret
;===============================================================
; subroutine getchr
; this routine reads in a chr from the serial port and saves it
; in the accumulator.
;===============================================================
getchr:
   jnb  ri, getchr        ; wait till character received
   mov  a,  sbuf          ; get character
   clr  ri                ; clear serial status bit
   ret
   
;===============================================================
; ERROR subroutines to be called when something cannot be executed
; and we need to let the PSoC know that something is wrong
;===============================================================
noMotorError:
	mov a, #01h
	lcall sndchr
	ret
	
noSpeedCtrlError:
	mov a, #03h
	lcall sndchr
	ret
	
noPositionCtrlError:
	mov a, #02h
	lcall sndchr
	ret

;===============================================================
; subroutine parsePSoCInput
; interprets the data received from the PSoC into either
; instructions/details or value data depending on the highest
; order bit (1: inst, 0: val)
;===============================================================
parsePSoCInput:
	jb acc.7, parseInst		;if acc.7 = 1, then we need to parse the instruction
	;if acc.7 = 0, then we have the value for speed/position, we can save it
	mov RHIGH, a			; a is restricted to between 0 and 100 (limits of RHIGH)
	lcall pwmSetup			;call this subroutine to update the pwm appropriately
	;clr p1.1				;debugging
	;mov p1, a				;debugging
	ret
	
parseInst:
	; acc.4 = 1: speed, 	 0: position
	; acc.3 = 1: positive, 0: negative
	; a[2:0] = motor ID number
			;mov p1, #0aah ;debug

	jb acc.4, setSpeed
	;TODO: POSITION CONTROL HERE
	jb POS_CTRL_UNAVAILABLE, noPositionCtrlError
	;
	;
	ret
	
setSpeed:
	jb SPD_CTRL_UNAVAILABLE, noSpeedCtrlError
	jb acc.3, setPOSspeed
	
setNEGspeed:
	anl a, #07h		;mask everything but the last 3 bits (they carry the desired motor id)
	jb acc.2, neg8Less
	jb acc.1, neg3Less
	negOneLess:
		jb acc.0, negMOTOR1	; #001b	= MOTOR#
		ljmp negMOTOR0		; #000b	= MOTOR#
	neg3Less:
		jb acc.0, negMOTOR3	; #011b	= MOTOR#
		ljmp negMOTOR2		; #010b	= MOTOR#
	neg8Less:
		jb acc.0, noMotorError
		jb acc.1, noMotorError
		;max 4 motors (at least for now)
		ljmp negMOTOR4		; #100b	= MOTOR#
setPOSspeed:
	anl a, #07h		;mask everything but the last 3 bits (they carry the desired motor id)
	;mov p1, a		;debug
	jb acc.2, pos8Less
	jb acc.1, pos3Less
	posOneLess:
		jb acc.0, posMOTOR1	; #001b	= MOTOR#
		ljmp posMOTOR0		; #000b	= MOTOR#
	pos3Less:
		jb acc.0, posMOTOR3	; #011b	= MOTOR#
		ljmp posMOTOR2		; #010b	= MOTOR#
	pos8Less:
		jb acc.0, noMotorError
		jb acc.1, noMotorError
		;max 4 motors (at least for now)
		ljmp posMOTOR4		; #100b	= MOTOR#

;===============================================================
; subroutines to control the speed of each of the motors
; contains subroutines for positive and negative directions,
; instructions/details or value data depending on the highest
; order bit (1: inst, 0: val)
;===============================================================
posMOTOR4:
	mov PORT_B_WRITE_DATA, #MOTOR4_POS_B
	mov PORT_C_WRITE_DATA, #00h
	ljmp writeMotorDataToPorts
negMOTOR4:
	mov PORT_B_WRITE_DATA, #MOTOR4_NEG_B
	mov PORT_C_WRITE_DATA, #00h
	ljmp writeMotorDataToPorts
	
posMOTOR3:
	mov PORT_B_WRITE_DATA, #MOTOR3_POS_B
	mov PORT_C_WRITE_DATA, #00h
	ljmp writeMotorDataToPorts
negMOTOR3:
	mov PORT_B_WRITE_DATA, #MOTOR3_NEG_B
	mov PORT_C_WRITE_DATA, #00h
	ljmp writeMotorDataToPorts
	
posMOTOR2:
	mov PORT_B_WRITE_DATA, #MOTOR2_POS_B
	mov PORT_C_WRITE_DATA, #00h
	ljmp writeMotorDataToPorts
negMOTOR2:
	mov PORT_B_WRITE_DATA, #MOTOR2_NEG_B
	mov PORT_C_WRITE_DATA, #00h
	ljmp writeMotorDataToPorts

posMOTOR1:
	mov PORT_B_WRITE_DATA, #MOTOR1_POS_B
	mov PORT_C_WRITE_DATA, #00h
	ljmp writeMotorDataToPorts
negMOTOR1:
	mov PORT_B_WRITE_DATA, #MOTOR1_NEG_B
	mov PORT_C_WRITE_DATA, #00h
	ljmp writeMotorDataToPorts

posMOTOR0:
	mov PORT_B_WRITE_DATA, #00h
	mov PORT_C_WRITE_DATA, #MOTOR0_POS_C
	ljmp writeMotorDataToPorts
negMOTOR0:
	mov PORT_B_WRITE_DATA, #00h
	mov PORT_C_WRITE_DATA, #MOTOR0_NEG_C
	ljmp writeMotorDataToPorts
	
writeMotorDataToPorts:
	; activate the correct motor (bit) in the correct port
	; and deactivate all other motors in the other port
	cpl p3.5
	mov dptr, #PORT_C_ADDR	
	mov a, PORT_C_WRITE_DATA
	anl a, STATUS
	movx @dptr, a
	mov dptr, #PORT_B_ADDR
	mov a, PORT_B_WRITE_DATA
	anl a, STATUS
	anl a, STATUS
	movx @DPTR, a
	;clr p1.6				;debugging
	mov a, #00h
	lcall sndchr			;communicate back to the PSoC That everything was received
	ret
	