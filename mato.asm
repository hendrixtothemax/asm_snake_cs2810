.data

.align 4
space: .asciz "   "
empty: .asciz "\033[38;5;130m.\033[0m"	// brown .
snake: .asciz "\033[32m@\033[0m"	// green @
tail: .asciz "\033[32mo\033[0m"		// green 0
border: .asciz "\033[33m#\033[0m"	// yellow #
bug1: .asciz "\033[38;5;199m\244\033[0m"// pink currency sing
bug2: .asciz "\033[38;5;207m~\033[0m"	// pink ~
bug3: .asciz "\033[38;5;165m\272\033[0m"// pink circle
clear_screen: .asciz "\033[2J\n"
move_up: .asciz "\033[1A"
hide_cursor: .asciz "\033[?25l"
show_cursor: .asciz "\033[?25h"
endl: .asciz "\n"
game_over: .asciz "\033[1A Game Over. Score: "
.align 4
map: .skip 600  		// mapxlen*mapylen*4
dx: .word 1			// snake directions
dy: .word 0
headx: .word 3			// snake head coords
heady: .word 3
max_len: .word 0		// snake length
random_seed: .word 0x1234	// updated from gettimeofday
rw_buffer: .skip 100
termios: .skip 100		// terminal input configs
saved_termios: .skip 100
delay_ticks: .word 800000000	// game speed for Samsung S10 -- for Raspberry Pi 3, use 230000000
.equ MAPXLEN, 14
.equ MAPYLEN, 8

.text
.global _start

///////////////////////////////////////////////
///////////////////  MAIN  ////////////////////
///////////////////////////////////////////////
_start:
	push {w4, lr}

	bl save_termios
	bl init_random_seed
	bl initialize_map

        ldr w0, =hide_cursor
        bl output

game_loop:

	bl move_and_check_collision	// update snake position
	cmp w0, #1			// did collision occur?
	beq the_end

	bl update_and_print_map

	bl check_keypress		// check if key was pressed
					// update dx and dy if needed
	b game_loop			// loop until collision

the_end:
	ldr w0, =game_over
	bl output
	ldr w0, =max_len
	ldr w0, [w0]
	bl output_int
	ldr w0, =endl
	bl output

	bl kbhit		// wait for any key
	bl cooked_mode		// just to be sure, restore termios

        ldr w0, =endl
        bl output
	ldr w0, =show_cursor
	bl output
	pop {w4, lr}
	
	mov w0, #0		// exit status 0 (ok)
    	mov w7, #1		// syscall 1 (exit)
    	svc #0

///////////////////////////////////////////////////
/////////////// END MAIN //////////////////////////
///////////////////////////////////////////////////




/////// MOVE AND CHECK SNAKE COLLISION ///////////
// Input: none
// Output: w0, =1 fatal collision, =0 no fatal collision
// Updates headx, heady. If collides with bug, increase max_len
// and go add a new bug
move_and_check_collision:
	push {w4, w5, w6, w7, w8, lr}
	ldr w4, =map

        ldr w1, =headx
        ldr w1, [w1]
        ldr w0, =dx
        ldr w0, [w0]
        add w5, w1, w0		// w5 = headx + dx
        ldr w2, =heady
        ldr w2, [w2]
        ldr w0, =dy
        ldr w0, [w0]
        add w6, w2, w0		// w6 = heady + dy
        mov w0, #MAPXLEN	// get map address for head (w3)
        mul w3, w6, w0
        add w3, w3, w5
        mov w0, #4
        mul w7, w3, w0		// (head) w7 = y*mapxlen + x

        ldr w0, [w4, w7]	// w0 = map point for next step
        cmp w0, #0              // collision to points >0 --> end
        bgt collision
        cmp w0, #-1             // -"- ==-1 --> end
        beq collision
        ldrlt w1, =max_len      // collision to bug --> maxlen++
        ldrlt w0, [w1]
        addlt w0, w0, #1
        strlt w0, [w1]
        bllt add_new_bug	// ...and go add a new bug

        mov w0, #1		// store new head point to map
        str w0, [w4, w7]
        ldr w0, =headx
        str w5, [w0] 		// store new headx
        ldr w0, =heady
        str w6, [w0]    	// store new heady

	mov w0, #0
	b end_move_and_coll
collision:
	mov w0, #1
end_move_and_coll:
	pop {w4, w5, w6, w7, w8, lr}
	ret
///////////////////////////////////////////////


/////// PRINT AND UPDATE MAP ///////////////////
// Input: none
// Output: none, updates and prints map
// Map is the main data structure for the game. Snake
// head is 0 ('@'), tail is increasing numbers 1,2,3,.. ('O').
// At each update step, tail is aged, and based on max_len,
// an empty space may be drawn instead: 0 ('.'). Borders
// are -1 ('#'). Different bugs are -2, -3, -4.
update_and_print_map:
	push {w4, w5, w6, w7, w8, lr}
	ldr w6, =map
        ldr w0, =clear_screen
        bl output

        mov w5, #0
mapy_loop:
        mov w4, #0
        cmp w5, #MAPYLEN
        beq end_map_loop
        add w5, w5, #1
	ldr w0, =space
	bl output
mapx_loop:
        cmp w4, #MAPXLEN
        ldreq w0, =endl
        bleq output
        cmp w4, #MAPXLEN
        beq mapy_loop
        add w4, w4, #1

        //// Update and print map point ////
        ldr w7, [w6]            // load map point

        cmp w7, #0              //if point is:
        addgt w0, w7, #1        //>0 --> increase its value +1
        strgt w0, [w6]          //i.e. snake tail get older
        ldreq w0, =empty        //==0 --> '.' to be printed
        cmp w7, #1
        ldreq w0, =snake        //==1 --> '@' head
        ldrgt w0, =tail         //>1 --> '0' tail
        cmp w7, #-1
        ldreq w0, =border       //==-1 --> '#'
        cmp w7, #-2             //==-2 --> '*'
        ldreq w0, =bug1
	cmp w7, #-3             //==-3 --> '~'
        ldreq w0, =bug2
	cmp w7, #-4             //==-4 --> '%'
        ldreq w0, =bug3


        ldr w1, =max_len        // cut tail if its too long
        ldr w1, [w1]
        add w1, w1, #1
        cmp w7, w1
        movgt w0, #0            // >max_len --> reset point to empty
        strgt w0, [w6]
        ldrgt w0, =empty

        bl output               // print the point

        add w6, w6, #4          // next  point in map
        b mapx_loop

end_map_loop:
	ldr w0, =endl
	bl output
	pop {w4, w5, w6, w7, w8, lr}
	ret
///////////////////////////////////////////////



/////////// CHECK KEYPRESS and UPDATE DX DY ///
// Input: none
// Output: none, update dx and dy
check_keypress:
	push {w4, w5, w6, lr}

      	bl raw_mode		// key presses are not buffered
      	bl delay
      	bl input
	ldr w4, [w0]
      	bl cooked_mode		// return to normal mode immediately
				// this is overkill, but helps when
				// debugging

      	//bl initscr            // For A LOT easier implementation,
        //bl noecho             // one could use ncurses C-library
        //bl cbreak             //
        //mov w0, #500          // wait 500ms for keypress
        //bl timeout            //
        //bl getch              // ncurses function: get non-blocking
 	//mov w4, w0            // keypress, store in w0
	//bl endwin		//

	cmp w4, #0x73           // 'w'
        moveq w0, #1
        beq update_dxdy

        cmp w4, #0x61           // 'a'
        moveq w0, #2
        beq update_dxdy

        cmp w4, #0x77           // 's'
        moveq w0, #3
        beq update_dxdy

        cmp w4, #0x64           // 'd'
        moveq w0, #4
        beq update_dxdy

	b end_check_keypress

update_dxdy:
	ldr w1, =dx
	ldr w2, =dy

	mov w4, #0	// new dx
	mov w5, #0	// new dy

	cmp w0, #1
        moveq w5, #1

        cmp w0, #2
        moveq w4, #-1

        cmp w0, #3
        moveq w5, #-1

        cmp w0, #4
        moveq w4, #1

	str w4, [w1]
	str w5, [w2]

end_check_keypress:
	pop {w4,w5, w6, lr}
	ret
//////////////////////////////////////


////////// INIT MAP /////////////////
// Input: none
// Output: none
// Initialize map values, mainly draw borders.
initialize_map:
	push {w4, lr}

	//horizontal borders//
	ldr w4, =map
	mov w0, #0
	mov w1, #MAPYLEN
	sub w2, w1, #1		// compute offset for bottom row
	mov w1, #MAPXLEN
	mul w2, w2, w1
	mov w1, #4
	mul w2, w2, w1
top_loop:
        cmp w0, #MAPXLEN
        beq end_top_loop
        add w0, w0, #1

	mov w1, #-1
	str w1, [w4]
	str w1, [w4, w2]  	// w2 is the offset for bottom row
	add w4, w4, #4
	b top_loop
end_top_loop:

	//vertical borders//
	ldr w4, =map
	mov w0, #0
        mov w1, #MAPXLEN
        sub w2, w1, #1          // compute offset for left row
	mov w3, #4
	mul w2, w2, w3
        mov w1, #MAPXLEN
        mul w3, w1, w3
side_loop:
	cmp w0, #MAPYLEN
	beq end_side_loop
        add w0, w0, #1

        mov w1, #-1
        str w1, [w4]
        str w1, [w4, w2]  	// w2 is offset for left row
        add w4, w4, w3   	// w3 is offset for next point
        b side_loop
end_side_loop:

	bl add_new_bug

	pop {w4, lr}
	ret
////////////////////////////////


////// ADD NEW BUG /////////////
// Input: none
// Output: none
// Adds a new random bug to the map in a random location
add_new_bug:
	push {w4, w5, w6, lr}
	ldr w4, =map
        mov w1, #MAPYLEN
        mov w2, #MAPXLEN
        mul w5, w1, w2          // mapylen*mapxlen
	bl get_random		// w0 = next random
	mov w1, #3
	bl divide		// w0 = w0 % 3
	cmp w0, #0
	moveq w6, #-2		// new bug '*'
	cmp w0, #1
        moveq w6, #-3	        // new bug '~'
        movgt w6, #-4         	// new bug '%'


add_bug_new_try:
	bl get_random		// w0 = next random
	mov w1, w5
	bl divide		// w0 / (mapylen*mapxlen)
				// --> w0 stores the modulo
	mov w3, #4
	mul w0, w0, w3  	// map address for new bug

	ldr w3, [w4, w0]	// load map point
	cmp w3, #0		// map point must be empty = 0 = '.'
	moveq w2, w6		// new bug: -2, -3, or -4
	streq w2, [w4, w0]	// store bug to map
	bne add_bug_new_try	// if not empty, try again

	pop {w4, w5, w6, lr}
	ret
/////////////////////////////////////


////// DIVISION (integer) ///////////
// Input: w0 (dividend), w1 (divisor), both integers
// Output: w0 (remainder, modulo), w1 (integer result of w0/w1)
divide:
	mov w2, #0
divide_loop:		// how many times w1 can be substr from w0?
	cmp w0, w1
	movlt w1, w2
	blt end_divide

	sub w0, w0, w1
	add w2, w2, #1  // increase counter
	b divide_loop

end_divide:
	ret
/////////////////////////////////////


//// NEXT RANDOM (positive) INT  ////
// Input: none
// Output: w0, next random number (positive)
// Takes random_seed from memory, updates the seed and returns it.
// Numbers are 2's complement, so lsr should make every number positive.
// Note that #1 shift would be enough for this purpose, but we want 
// small random numbers so calculating the following modulo is fast
get_random:
	ldr w1, =random_seed
	ldr w0, [w1]
	add w0, w0, #137
	eor w0, w0, w0, ror #13
	lsr w0, w0, #5	//shift right to ensure positiveness
	str w0, [w1]

	ret
/////////////////////////////////////


///////// INIT RANDOM SEED //////////
// Input: none
// Output: none, updates random_seed
// Makes a software interrupt by supervisor call to gettimeofday
// Interrupt numbers from: https://syscalls.w3challs.com/?arch=arm_strong
// For Raspberry Pi, replace 9 in 0x900.. with 0
init_random_seed:
        push {w7, lr}
        ldr w0, =random_seed
        mov w7, #0x00004e	// syscall for gettimeofday
        svc #0

        pop {w7, lr}
        ret
/////////////////////////////////////


////// OUTPUT //////////////////////
// Input: w0, address of string to print
// Output: none, prints to stdout
output:
	push {w4, w6, w7, lr}
	mov w4, w0		// store orig addr of string
	mov w3, #0
count_loop:			// count chars in the string
	ldrb w1, [w0], #1	// each char is one byte
	cmp w1, #0		// each string must be null-ended
	beq next_print
	addne w3, w3, #1
	b count_loop
next_print:
	mov w0, #1              // stdout
    	mov w1, w4	        // address of the string
    	mov w2, w3             	// string length
    	mov w7, #4              // syscall for 'write'
    	svc #0                  // software interrupt
	pop {w4, w6, w7, lr}
	ret
////////////////////////////////////


////// INPUT ///////////////////////
// Input: none
// Output: address of input string =rw_buffer
input:
	push {w4, w6, w7, lr}
	ldr w4, =rw_buffer
	mov w1, #0
	str w1, [w4]
	str w1, [w4, #+4]	// make sure buffer is empty

	mov w0, #0              // stdin
        mov w1, w4              // address of the string
        mov w2, #1              // string length = 1
        mov w7, #3              // syscall for 'write'
        svc #0                  // software interrupt

	mov w0, w4		//return address of string

end_input:
	nop
	pop {w4, w6, w7, lr}
        ret
////////////////////////////////////////////////


////// OUTPUT INTEGER TO PRINT AS STRING ///////
// Input: w0, 32 bit positive integer
// Output: none, prints w0 to stdout as decimal
output_int:
	push {w4, w5, w6, lr}
	mov w4, w0
    	mov w5, #8		// word is 8 x 4 bits
	mov w6, #0		// carry
	ldr w3, =rw_buffer	// buffer to write string
	add w3, w3, #7		// start writing from end
output_int_loop:
    	// Take least significant 4 bits from w4 into w0, loop 8 times
    	mov w0, w4, lsl #28
	mov w0, w0, lsr #28

	cmp w6, #0		// add carry if previous round >9
	addgt w0, w0, #1
	movgt w6, #0

	cmp w0, #9		// check if >9, if so mark carry
	subgt w0, w0, #10
	movgt w6, #1

    	mov w4, w4, lsl #4	// Shift w4 for next time

    	// For each nibble (now in w0) convert to ASCII
    	add w0, w0, #48
	strb w0, [w3], #-1

    	sub w5, w5, #1		// decrease loop counter
	cmp w5, #0
    	bne output_int_loop

	ldr w0, =rw_buffer	// reset to start
	mov w2, #6
output_int_loop3:		// skip leading zeroes (max 7)
	ldrb w1, [w0]
	cmp w1, #0x30		//= "0" in ascii
	addeq w0, w0, #1
	bne output_int_end
	subs w2, w2, #1
	bmi output_int_end	//if last number is also 0, print it
	b output_int_loop3
output_int_end:
	bl output

	pop {w4, w5, w6, lr}
	ret
////////////////////////////////////////////


////////DELAY///////////////////////////
// Input, Output: none
// Delay program for delay_ticks loop time
delay:
        ldr w0, =delay_ticks
        ldr w0, [w0]
        mov w1, #0
delay_loop:
        cmp w1, w0
        add w1, w1, #1
        blt delay_loop

        ret
////////////////////////////////////////


///// KBHIT ////////////////////////////
// Input, Output: none
// Wait for any key press
kbhit:
        push {w4, lr}
        bl cbreak_off
        bl input
        bl cooked_mode
        pop {w4, lr}
        ret
////////////////////////////////////////



///////////////////////////////////////////////////////
//        TERMIOS MANIPULATION FUNCTIONS
// Controls how data is buffered and read from keyboard
///////////////////////////////////////////////////////
//struct termios {
//    tcflag_t c_iflag;               // input mode flags
//    tcflag_t c_oflag;               // output mode flags
//    tcflag_t c_cflag;               // control mode flags
//    tcflag_t c_lflag;               // local mode flags
//    cc_t c_line;                    // line discipline
//    cc_t c_cc[NCCS];                // control characters
//};
///////////////////////////////////////////////////////
// Input, Output: none
// Saves current termios (terminal input) configs to memory.
// Needed so that they can be restored after config changes.
save_termios:
        push {w4, lr}
        bl read_termios
        ldr w0, =termios
        mov w1, #0
        ldr w2, =saved_termios
loop_save:                      // save old configurations
        cmp w1, #11
        beq end_loop_save
        ldr w3, [w0], #4
        str w3, [w2], #4
        add w1, w1, #1
        b loop_save
end_loop_save:
	pop {w4, lr}
	ret
//////////////////////////////////////////////
// Input, Output: none
// Change input mode to raw mode. Input is not buffered.
// Needed to immediate reading of data from keypresses.
// Following instructions in:
// https://sourceforge.net/p/hla-stdlib/mailman/hla-stdlib-talk/
//         thread/814462.63171.qm@web65510.mail.ac4.yahoo.com/
// Flag values from:
// https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/
//         linux.git/tree/include/uapi/asm-generic/termbits.h?id=HEAD
raw_mode:
	push {w4, w5, w6, w7, w8, lr}

	bl save_termios

	ldr w0, =termios
	//termattr.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
	mov w1, #1000
	orr w1, w1, #2
	orr w1, w1, #0100000
	orr w1, w1, #01
	mvn w1, w1
	ldr w6, [w0, #+12]
	and w6, w6, w1
	str w6, [w0, #+12]
   	//termattr.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
	mov w2, #2
	orr w2, #400
	orr w2, #20
	orr w2, #2000
	mvn w2, w2
	ldr w6, [w0]
        and w6, w6, w2
        str w6, [w0]
  	//termattr.c_cflag &= ~(CSIZE | PARENB);
	mov w3, #60
	orr w3, #400
	mvn w3, w3
	ldr w6, [w0, #+8]
        and w6, w6, w3
   	//termattr.c_cflag |= CS8;
	mov w4, #60
        orr w6, w6, w4
        str w6, [w0, #+8]
   	//termattr.c_oflag &= ~(OPOST);
	mvn w5, #1
 	ldr w6, [w0, #+4]
        and w6, w6, w5
        str w6, [w0, #+4]
	//termattr.c_cc[VMIN] = 1;  // or 0 for some Unices 
   	mov w7, #0		// needs to be 0 for Raspbian
	strb w7, [w0, #+23]	// 16 + 1 + 6 (VMIN) 
	//termattr.c_cc[VTIME] = 0;
	mov w8, #0
	strb w8, [w0, #+22]	// 16 + 1 + 5 (VTIME)

	bl write_termios
	pop {w4, w5, w6, w7, w8, lr}
	ret
/////////////////////////////////////////
// Input, Output: none
// Set input mode to normal mode. Needs pre-saved termios
// structure saved in save_termios. Make sure to call this
// at the end of program, or your terminal input is toast.
cooked_mode:
	push {w4, lr}
	ldr w0, =termios
        mov w1, #0
        ldr w2, =saved_termios
loop_load:                      // load old configurations
        cmp w1, #11
        beq end_loop_load
        ldr w3, [w2], #4
        str w3, [w0], #4
        add w1, w1, #1
	b loop_load
end_loop_load:

	bl write_termios
	pop {w4, lr}
	ret
/////////////////////////////////////////
// Input, Output: none
// Don't wait for a newline in following inputs
cbreak_off:
        push {w7, lr}
        bl read_termios

        ldr w0, =termios
        ldr w1, [w0, #+12]!
	mvn w2, #0x00000002 	// NOT ICANON flag
        and w1, w1, w2		// AND local flag
	mvn w2, #1000		// NOT ECHO flag
	and w1, w1, w2		// AND local flag
        str w1, [w0]            // store back to termios+12

        bl write_termios
        pop {w7, lr}
        ret
//////////////////////////////////////////
// Input, Output: none
// Wait for newline to buffer input, as normal
cbreak_on:
	push {w7, lr}
        bl read_termios

	ldr w0, =termios
	ldr w1, [w0, #+12]!
	mov w2, #0x00000002	// ICANON flag
	orr w1, w1, w2		// canonical bit ON in local mode flags
        mov w2, #1000           // ECHO flag
        and w1, w1, w2
	str w1, [w0]		// store back to termios+12

        bl write_termios
	pop {w7, lr}
	ret
//////////////////////////////////////////
// Input, Output: none
// Make syscall to ioctl and read termios structure to memory
read_termios:
        push {w7, lr}

	mov w0,	#0		// stdin
	ldr w1, =#0x5401 	// READ termios parameters
	ldr w2, =termios	// address for termios buffer
	mov w7, #54		// syscall for ioctl 0x36
	svc #0

        pop {w7, lr}
        ret
/////////////////////////////////////////
// Input, Output: none
// Make syscall to ioctl and input termios structure to system
write_termios:
        push {w7, lr}

        mov w0, #0              // stdin
        ldr w1, =#0x5402        // WRITE termios parameters
        ldr w2, =termios        // address for termios buffer
        mov w7, #54             // syscall for ioctl 0x36
        svc #0

        pop {w7, lr}
        ret
//////////////////////////////////////////
