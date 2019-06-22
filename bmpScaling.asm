#   EN: A project created for Computer Architecture lectures at Warsaw University of Technology
#       Scaling BMP image with MIPS Assembly
#       Calculations base on fixed-point arithmetic
#       Tested in MARS 4.5
#
#   PL: Projekt ARKO (Architektura Komputerow) PW WEiTI 18Z
#       Skalowanie obrazka BMP z wykorzystaniem jezyka MIPS
#       Obliczenia bazuja na zapisie stalopozycyjnym
#       Testowane w srodowisku MARS 4.5
#
#   Copyright (C) Robert Dudzinski 2018
#   Warsaw, November 2018

#system calls
.eqv 	SC_OPEN_FILE 13
.eqv	SC_READ_FILE 14
.eqv	SC_WRITE_FILE 15
.eqv	SC_CLOSE_FILE 16

.eqv	IO_PRINT_STRING 4
.eqv	IO_READ_STRING 8

.eqv	IO_PRINT_INT 1
.eqv	IO_READ_INT 5

#defining the size of in-buffer
.eqv	ROWS_BUFFER_DOUBLE 16  # must be a power of 2
.eqv	ROWS_BUFFER_SINGLE 8   # = ROWS_BUFFER_DOUBLE / 2
.eqv	ROWS_BUFFER_MODULO 28  # = 32 - log2(ROWS_BUFFER_DOUBLE) = 32 - log2(16) = 32 - 4 = 28

#point number: bytes per mantissa and integer parts: POINT_MAN + POINT_INT = 32
.eqv	POINT_MAN 8
.eqv	POINT_INT 24

#defining the size of out-buffer
.eqv 	OUT_BUF_SIZE 10000
	
.data
question_filename:	.asciiz "Enter name of source file: "
question_width:		.asciiz "Enter new width: "
question_height:	.asciiz "Enter new height: "
result_msg:		.asciiz "Result stored at dst.bmp"
err_src_msg:		.asciiz "Can't open src file"
err_dst_msg:		.asciiz "Can't open dst file"
err_input_msg:		.asciiz "Wrong data input"

inbuf:			.space 250000		#for 250000 and ROWS_BUFFER_DOUBLE=16: max width of src image = 3900
outbuf:			.space OUT_BUF_SIZE
src:			.space 256
dst:			.asciiz "dst.bmp"

.text
.globl main
	
#REGISTERS:
#s0 - src file
#s1 - dst file
#s2 - w: original width
#s3 - h: original height
#s4 - nw: new width
#s5 - nh: new height
#s6 - writeptr: byte counter of out-buffer
#s7 - lastLineIndex: index of the last line in in-buffer

#t8 - iterator Y; iterating over each line of new image
#t9 - iterator X; iterating over each channel in the line of new image

#t0 - remaing bytes in the header; C2
#t1 - C1; temporally stores OY after $t2
#t2 - offx; newp; help variable when loading to inbuf; temporally stores OY after $t6
#t3 - fx
#t4 - fy
#t5 - OX
#t6 - OY; lerp1
#t7 - offy, lerp2

#When projecting new pixel position on original bitmap:
#fx - mantissa
#fy - mantissa
#OX - floor
#OY - floor

#Finding channel value in in-buffer:
#offx - X offset when finding in-line index of in-buffer
#offy - Y offset when finding a line in in-buffer

#C1, C2 - values of channels; used as parameters when calculating lerp1 and lerp2
#lerp1 - interpolation between C1 and C2 for 1st and 2nd channel
#lerp2 - interpolation between C1 and C2 for 3rd and 4th channel
#newp - final value of channel; interpolation between lerp1 and lerp2
	
main:
	#get name of src file
	li $v0, IO_PRINT_STRING
	la $a0, question_filename
	syscall
	
	li $v0, IO_READ_STRING
	la $a0, src
	li $a1, 256
	syscall
	
	#fix given filename
	la $t0, src
next_char:
	addiu $t0, $t0, 1
	lbu $t1, ($t0)
	bge $t1, 32, next_char
	sb $zero, ($t0)

	#read new width from the user
	li $v0, IO_PRINT_STRING
	la $a0, question_width
	syscall
	
	li $v0, IO_READ_INT
	syscall
	ble $v0, $zero, error
	move $s4, $v0
	
	#read new height from the user
	li $v0, IO_PRINT_STRING
	la $a0, question_height
	syscall
	
	li $v0, IO_READ_INT
	syscall
	ble $v0, $zero, error
	move $s5, $v0

	#open src and dst file
	li $v0, SC_OPEN_FILE
	la $a0, src
	li $a1, 0
	li $a2, 0
	syscall
	beq $v0, $zero, cant_open_src
	move $s0, $v0
	
	li $v0, SC_OPEN_FILE
	la $a0, dst
	li $a1, 1
	li $a2, 0
	syscall
	blt $v0, $zero, cant_open_dst
	move $s1, $v0
	
	#read first 14+3*4 bytes of the header and copy first 18
	li $v0, SC_READ_FILE
	move $a0, $s0
	la $a1, inbuf
	li $a2, 26
	syscall
	
	li $v0, SC_WRITE_FILE
	move $a0, $s1
	la $a1, inbuf
	li $a2, 18
	syscall
	
	#read int from 14th byte - number of bytes remaining in this header
	ulw $t0, inbuf+14
	subiu $t0, $t0, 12
	
	#read resolution of src file
	ulw $s2, inbuf+18
	ulw $s3, inbuf+22
	
	#save resolution of dst file
	usw $s4, inbuf+18
	usw $s5, inbuf+22
	
	li $v0, SC_WRITE_FILE
	move $0, $s1
	la $a1, inbuf+18
	li $a2, 8
	syscall
	
	#copy the rest of the header using int from 14th byte
	li $v0, SC_READ_FILE
	move $a0, $s0
	la $a1, inbuf
	move $a2, $t0
	syscall
	
	li $v0, SC_WRITE_FILE
	move $a0, $s1
	la $a1, inbuf
	move $a2, $t0
	syscall
	
	#fill empty inbuf
	mulu $s2, $s2, 4
	mulu $s2, $s2, ROWS_BUFFER_DOUBLE
	#mulu $s2, $s2, 32
	
	li $v0, SC_READ_FILE
	move $a0, $s0
	la $a1, inbuf
	move $a2, $s2
	syscall
	
	divu $s2, $s2, ROWS_BUFFER_DOUBLE
	#divu $s2, $s2, 32
	divu $s2, $s2, 4
	
	li $s7, ROWS_BUFFER_DOUBLE
	#li $s7, 32
	addiu $s7, $s7, -1
	
	#loop iterating over rows
	mulu $s4, $s4, 4
	li $t8, 0
row_loop:
	
	#inner loop: iterates over channels (columns)
	li $t9, 0
channel_loop:	
#calculate fx fy ox oy
	#fx = x / nw * (w - 1)
	addiu $t3, $s2, -1
	mulu $t3, $t3, $t9
	#switch int to point number
	sll $t3, $t3, POINT_MAN
	div $t3, $t3, $s4
	
	#fy = y / nh * (h - 1)
	addiu $t4, $s3, -1
	mulu $t4, $t4, $t8
	#switch int to point number
	sll $t4, $t4, POINT_MAN
	div $t4, $t4, $s5
	
	#get floor values (as integers)
	move $t5, $t3
	srl $t5, $t5, POINT_MAN
	move $t6, $t4
	srl $t6, $t6, POINT_MAN
	
	#get mantissa values (as point numbers)
	sll $t3, $t3, POINT_INT
	srl $t3, $t3, POINT_INT
	sll $t4, $t4, POINT_INT
	srl $t4, $t4, POINT_INT
	
#find two first pixels (channel)
	
	#offy = (oy%16) * w * 4
	move $t7, $t6
	sll $t7, $t7, ROWS_BUFFER_MODULO
	srl $t7, $t7, ROWS_BUFFER_MODULO
	mulu $t7, $t7, $s2
	mulu $t7, $t7, 4
	
	#offx = x%4 + 4*ox
	move $t2, $t9
	#modulo 4
	sll $t2, $t2, 30
	srl $t2, $t2, 30
	addu $t2, $t2, $t5
	addu $t2, $t2, $t5
	addu $t2, $t2, $t5
	addu $t2, $t2, $t5
	
	#offy += offx
	addu $t7, $t7, $t2
	
	#check if required bytes are in inbuf; if not update inbuf
	bge $t6, $s7, update_inbuf0
	
return_after_bufor_update0:
	#get first pixel (channel)
	lbu $t1, inbuf($t7)
	
	#get second pixel (channel)
	addi $t7, $t7, 4
	lbu $t0, inbuf($t7)
	
#find 3th and 4th pixel (channel)
	
	#offy = (oy+1)%16 * w * 4 + offx
	move $t7, $t6
	addiu $t7, $t7, 1
	sll $t7, $t7, ROWS_BUFFER_MODULO
	srl $t7, $t7, ROWS_BUFFER_MODULO
	mulu $t7, $t7, $s2
	mulu $t7, $t7, 4
	addu $t7, $t7, $t2
	
	#calculate interpolation between first two pixels (channels): p1 + (p2 - p1) * fx
	sub $t6, $t0, $t1
	mulu $t6, $t6, $t3
	sll $t1, $t1, POINT_MAN
	addu $t6, $t6, $t1
	
	#get 3rd pixel (channel)
	lbu $t1, inbuf($t7)
	
	#get 4th pixel (channel)
	addi $t7, $t7, 4
	lbu $t0, inbuf($t7)
	
	#calculate interpolantion between 3rd and 4th pixel (channels): p3 + (p4 - p3) * fx
	sub $t7, $t0, $t1
	mulu $t7, $t7, $t3
	sll $t1, $t1, POINT_MAN
	addu $t7, $t7, $t1
	
#calculate bilinear interpolation between 4 pixels (channels): lerp12 + (lerp34 - lerp12) * fy
	sub $t2, $t7, $t6
	#convert this point number to int
	srl $t2, $t2, POINT_MAN
	mulu $t2, $t2, $t4
	addu $t2, $t2, $t6
	
	#save calculated pixel (channel) to outbuf
	srl $t2, $t2, POINT_MAN
	sb $t2, outbuf($s6)
	addiu $s6, $s6, 1
	
	#check if outbuf if full
	bge $s6, OUT_BUF_SIZE, push_outbuf_to_file
	
	#ending inner loop
	addiu $t9, $t9, 1
	blt $t9, $s4, channel_loop
	#ending outer loop
	addiu $t8, $t8, 1
	blt $t8, $s5, row_loop
	
epilog:
	#if outbuf contains data, save it to file
	li $v0, SC_WRITE_FILE
	move $a0, $s1
	la $a1, outbuf
	move $a2, $s6
	syscall

	#close both files
	li $v0, SC_CLOSE_FILE
	move $a0, $s0
	syscall
	
	li $v0, SC_CLOSE_FILE
	move $a0, $s1
	syscall
	
	li $v0, IO_PRINT_STRING
	la $a0, result_msg
	syscall
	
	li $v0, 10
	syscall
	
push_outbuf_to_file:
	li $v0, SC_WRITE_FILE
	move $a0, $s1
	la $a1, outbuf
	move $a2, $s6
	syscall
	li $s6, 0

	#ending inner loop
	addiu $t9, $t9, 1
	blt $t9, $s4, channel_loop
	#ending outer loop
	addiu $t8, $t8, 1
	blt $t8, $s5, row_loop
	
	j epilog
	
update_inbuf0:
	move $t1, $t2
	mulu $s2, $s2, 4
	
load_more:	
	#help = lastLineIndex%16 * w
	addiu $s7, $s7, 1
	move $t2, $s7
	sll $t2, $t2, ROWS_BUFFER_MODULO
	srl $t2, $t2, ROWS_BUFFER_MODULO
	mulu $t2, $t2, $s2
	addiu $s7, $s7, -1
	
	#read next ROWS_BUFFER_SINGLE lines of pixels from the file
	mulu $s2, $s2, ROWS_BUFFER_SINGLE
	li $v0, SC_READ_FILE
	move $a0, $s0
	la $a1, inbuf($t2)
	move $a2, $s2
	syscall
	divu $s2, $s2, ROWS_BUFFER_SINGLE
	
	#lastLineIndex += 8
	addiu $s7, $s7, ROWS_BUFFER_SINGLE
	
	bge $t1, $s7, load_more
	divu $s2, $s2, 4
	
	j return_after_bufor_update0
	
cant_open_src:
	li $v0, IO_PRINT_STRING
	la $a0, err_src_msg
	syscall
	
	li $v0, 10
	syscall

cant_open_dst:
	li $v0, IO_PRINT_STRING
	la $a0, err_dst_msg
	syscall
	
	#close src file
	li $v0, SC_CLOSE_FILE
	move $a0, $s0
	syscall
	
	li $v0, 10
	syscall
	
error:
	li $v0, IO_PRINT_STRING
	la $a0, err_input_msg
	syscall
	
	li $v0, 10
	syscall
