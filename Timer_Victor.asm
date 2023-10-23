
; ISR_example.asm: a) Increments/decrements a BCD variable every half second using
; an ISR for timer 2; b) Generates a 2kHz square wave at pin P1.1 using
; an ISR for timer 0; and c) in the 'main' loop it displays the variable
; incremented/decremented using the ISR for timer 2 on the LCD.  Also resets it to 
; zero if the 'BOOT' pushbutton connected to P4.5 is pressed.
$NOLIST
$MODLP51RC2
$LIST

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

SOUND_OUT     equ P1.1

ALARM_TOGGLE  EQU P0.0
ADD_AMINUTES  EQU P0.4
ADD_AHOURS	  EQU P0.6
ADD_MINUTES	  EQU P4.5
ADD_HOURS	  EQU P2.4
SNOOZE		  EQU P2.0

; Reset vector
org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
Count1ms:     ds 2 ; Used to determine when one second has passed
SECONDS_counter:  ds 1 
MINUTES_counter:  ds 1
HOURS_counter:	  ds 1
ALARM_HOURS:	  ds 1
ALARM_MINUTES:	  ds 1


; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:
bseg
one_second_flag: dbit 1 ; Set to one in the ISR every time 1000 ms had passed
AMPM_Flag: dbit 1 ; flag for AorP
AorP: dbit 1 ; AM or PM
Alarm_Flag: dbit 1 ; flag for Alarm Message
ALARM_AMPM_Flag: dbit 1 ; flag for AorP
ALARM_AorP: dbit 1 ; AM or PM

cseg
; These 'equ' must match the hardware wiring
LCD_RS equ P3.2
;LCD_RW equ PX.X ; Not used in this code, connect the pin to GND
LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7


$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

;                   1234567890123456    <- This helps determine the location of the counter
Alarm_Message:  db '##:## *M   ALARM', 0
Clock_Message:  db '##:##:## *M  ***', 0
ON_MESSAGE: 	db 'ON ', 0
OFF_MESSAGE: 	db 'OFF', 0

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
	mov a, TMOD
	anl a, #0xf0 ; 11110000 Clear the bits for timer 0
	orl a, #0x01 ; 00000001 Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	; Set autoreload value
	mov RH0, #high(TIMER0_RELOAD)
	mov RL0, #low(TIMER0_RELOAD)
	; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    setb TR0  ; Start timer 0
	ret

;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz square wave at pin P1.1 ;
;---------------------------------;
Timer0_ISR:
	clr TF0  ; According to the data sheet this is done for us already.
	cpl SOUND_OUT ; Connect speaker to P1.1!
	
	reti

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer2_Init:
	mov HOURS_counter, #0x12
	clr AMPM_Flag
	mov AorP, #'A'
	clr ALARM_AMPM_Flag
	mov ALARM_AorP, #'A'
	
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)
	; Set the reload value
	mov RCAP2H, #high(TIMER2_RELOAD)
	mov RCAP2L, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
    setb ET2  ; Enable timer 2 interrupt
    setb TR2  ; Enable timer 2
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	cpl P1.0 ; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
		
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:
	; Check if 1 second has passed
	mov a, Count1ms+0
	cjne a, #low(100), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(100), Timer2_ISR_done
	
	; 1000 milliseconds have passed.  Set a flag so the main program knows
	setb one_second_flag ; Let the main program know one second had passed
	cpl TR0 ; Enable/disable timer/counter 0. This line creates a beep-silence-beep-silence sound.
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	
	; Increment the seconds counter
	mov a, SECONDS_counter
	
	jnb ADD_HOURS, Timer2_Increment_Hours
	
	jnb ADD_MINUTES, Timer2_Increment_Minutes
	
	add a, #0x01
	sjmp Timer2_ISR_da
	
Timer2_ISR_da:
	da a ; Decimal adjust instruction.  Check datasheet for more details!
	mov SECONDS_counter, a

Timer2_Check_Minute_Passed:
	cjne a, #0x60, Timer2_ISR_done
	ljmp Timer2_Reset_Seconds
	
Timer2_Reset_Seconds:
	mov SECONDS_counter, #0x00
Timer2_Increment_Minutes:
	; Increment the minutes counter
	mov a, MINUTES_counter
	add a, #0x01
	da a
	mov MINUTES_counter, a
	
Timer2_Check_Hour_Passed:
	cjne a, #0x60, Timer2_ISR_done
	ljmp Timer2_Reset_Minutes

Timer2_Reset_Minutes:
	mov MINUTES_counter, #0x00
Timer2_Increment_Hours:
	; Increment the hours counter
	mov a, HOURS_counter
	add a, #0x01
	da a
	mov HOURS_counter, a
	
	cjne a, #0x12, Timer2_Check_12_Hours_Passed ; Check if it it time to switch AM/PM

Timer2_Switch_AM_PM:
	cpl AMPM_Flag
	jb AMPM_Flag, Set_PM
	mov AorP, #'A'
	sjmp Timer2_Check_12_Hours_Passed
	
Set_PM:
	mov AorP, #'P'
	
Timer2_Check_12_Hours_Passed:
	mov a, HOURS_counter
	cjne a, #0x13, Timer2_ISR_done
	ljmp Timer2_Reset_Hours
	
Timer2_Reset_Hours:
	mov HOURS_counter, #0x01
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti

;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;
main:
	; Initialization
    mov SP, #0x7F
    lcall Timer0_Init
    lcall Timer2_Init
    ; In case you decide to use the pins of P0, configure the port in bidirectional mode:
    mov P0M0, #0
    mov P0M1, #0
    setb EA   ; Enable Global interrupts
    lcall LCD_4BIT
    ; For convenience a few handy macros are included in 'LCD_4bit.inc':
		
    Set_Cursor(1, 1)
    Send_Constant_String(#Alarm_Message)
	
	Set_Cursor(2, 1)
    Send_Constant_String(#Clock_Message)
    
    clr ALARM_Flag
    Set_Cursor(2,14)
	Send_Constant_String(#OFF_Message)
    
    mov ALARM_HOURS, #0x12
    Set_Cursor(1,1)
	Display_BCD(ALARM_HOURS)
    
    mov ALARM_MINUTES, #0x00
    Set_Cursor(1,4)
	Display_BCD(ALARM_MINUTES)
	
    Set_Cursor(1,7)
	Display_char(#'A')
    
    
    setb 	one_second_flag
	mov SECONDS_counter, #0x00
	mov MINUTES_counter, #0x00
	
		
	; After initialization the program stays in this 'forever' loop	
top_of_loop:

;setb ET0
	
check_ALARM_TIME_ADD_MINUTES:	
	jb ADD_AMINUTES, check_ALARM_TIME_ADD_HOURS
	Wait_Milli_Seconds(#50)
	jb ADD_AMINUTES, check_ALARM_TIME_ADD_HOURS
	jnb ADD_AMINUTES, $
	ljmp ALARM_Increment_Minutes


check_ALARM_TIME_ADD_HOURS:
	jb ADD_AHOURS, check_ALARM_TOGGLE
	Wait_Milli_Seconds(#50)
	jb ADD_AHOURS, check_ALARM_TOGGLE
	jnb ADD_AHOURS, $
	ljmp ALARM_Increment_Hours

ALARM_Increment_Minutes:
	; Increment the ALARM minutes counter
	mov a, ALARM_MINUTES
	add a, #0x01
	da a
	mov ALARM_MINUTES, a
	
ALARM_Check_Hour_Passed:
	cjne a, #0x60, check_ALARM_TIME_ADD_HOURS
	ljmp ALARM_Reset_Minutes

ALARM_Reset_Minutes:
	mov ALARM_MINUTES, #0x00
ALARM_Increment_Hours:
	mov a, ALARM_HOURS
	add a, #0x01
	da a
	mov ALARM_HOURS, a
	
	cjne a, #0x12, ALARM_Check_12_Hours_Passed ; Check if it it time to switch AM/PM

ALARM_Switch_AM_PM:
	cpl ALARM_AMPM_Flag
	jb ALARM_AMPM_Flag, ALARM_Set_PM
	mov ALARM_AorP, #'A'
	sjmp ALARM_Check_12_Hours_Passed
	
ALARM_Set_PM:
	mov ALARM_AorP, #'P'
	
ALARM_Check_12_Hours_Passed:
	mov a, ALARM_HOURS
	cjne a, #0x13, check_ALARM_TIME_ADD_MINUTES
	ljmp ALARM_Reset_Hours
	
ALARM_Reset_Hours:
	mov ALARM_HOURS, #0x01
	

check_ALARM_TOGGLE:
	jb ALARM_TOGGLE, check_BEEPS
	Wait_Milli_Seconds(#50)
	jb ALARM_TOGGLE, check_BEEPS
	jnb ALARM_TOGGLE, $
	cpl Alarm_Flag
	
	jb Alarm_Flag, ALARM_TOGGLE_ON
	; Alarm OFF, ALARM_Flag is 0
	Set_Cursor(2,14)
	Send_Constant_String(#OFF_Message)
    ljmp check_BEEPS    

ALARM_TOGGLE_ON:
	; Alarm ON, ALARM_Flag is 1
	Set_Cursor(2,14)
	Send_Constant_String(#ON_Message)
    
check_BEEPS:
	mov a, HOURS_counter
	mov b, ALARM_HOURS
	cjne a, b, NO_BEEPS
	
	mov a, MINUTES_counter
	mov b, ALARM_MINUTES
	cjne a, b, NO_BEEPS

	jnb Alarm_Flag, NO_BEEPS
	
	jb AMPM_Flag, BEEP_PM_CONTROL
	
	ljmp BEEP_AM_CONTROL
	
BEEP_PM_CONTROL:
	
	jnb ALARM_AMPM_Flag, NO_BEEPS
	
	setb ET0
	ljmp display_clock
	
BEEP_AM_CONTROL:

	jb ALARM_AMPM_Flag, NO_BEEPS
	
	setb ET0
	ljmp display_clock
	
NO_BEEPS:
	clr ET0
	ljmp display_clock	
	
	
	
display_clock:
    clr one_second_flag ; We clear this flag in the main loop, but it is set in the ISR for timer 2
    
	Set_Cursor(1,1)
	Display_BCD(ALARM_HOURS)
	
	Set_Cursor(1,4)
	Display_BCD(ALARM_MINUTES)
	
	Set_Cursor(1,7)
	Display_char(ALARM_AorP)
	
    
	Set_Cursor(2, 1)
	Display_BCD(HOURS_counter)
	
	Set_Cursor(2, 4)
	Display_BCD(MINUTES_counter)
	
	Set_Cursor(2, 7)
	Display_BCD(SECONDS_counter)
	
	Set_Cursor(2, 10)
    Display_char(AorP)
    
    
	ljmp top_of_loop
	
END
