/*
 * File: os.S
 * Description: Example of how to enable virtual memory and load and run a user program.
 */

#define USER_PA 0x80005000
#define USER_VA 0x80001000
#define USER_PA_2 0x80007000
#define USER_VA_2 0x80006000

#define KERNEL_PA 0x80000000
#define PT2_PA 0x80002000
#define PT1_PA 0x80003000
#define PT0_PA 0x80004000

#define PN(PA) (PA >> 12)
#define PN0(PA) (PA >> 12 & 0x1ff)
#define PN1(PA) (PA >> 21 & 0x1ff)
#define PN2(PA) (PA >> 30 & 0x1ff)

.text
.global _start;

_start:
.align 2
bootloader:

        # Init PT2
        li t2, PT2_PA + 8*PN2(PT1_PA);
        li t3, (PN(PT1_PA) << 10) | 0x1; # pointer to PT1
        sw t3, 0(t2);

        # Init PT1
        li t2, PT1_PA + 8*PN1(PT0_PA);
        li t3, (PN(PT0_PA) << 10) | 0x1; # pointer to PT0
        sw t3, 0(t2);

        # Init PT0
        # Set KERNEL_PA->KERNEL_PA
        li t2, PT0_PA + 8*PN0(KERNEL_PA);
        li t3, (PN(KERNEL_PA) << 10) | 0xef;
        sw t3, 0(t2);
        # Set PT2_PA->PT2_PA
        li t2, PT0_PA + 8*PN0(PT2_PA);
        li t3, (PN(PT2_PA) << 10) | 0xef;
        sw t3, 0(t2);
        # Set PT1_PA->PT1_PA
        li t2, PT0_PA + 8*PN0(PT1_PA);
        li t3, (PN(PT1_PA) << 10) | 0xef;
        sw t3, 0(t2);
        # Set PT0_PA->PT0_PA
        li t2, PT0_PA + 8*PN0(PT0_PA);
        li t3, (PN(PT0_PA) << 10) | 0xef;
        sw t3, 0(t2);

        # cfig PMP
        # entry0: addr 0x0_0000_0000~0x2_ffff_ffff, l=0 a=1 x=1 w=1 r=1
        li   x1, 0x0f;
        csrw pmpcfg0, x1;
        li   x1, 0xc0000000;
        csrw pmpaddr0, x1;

	la t2, m_trap;
        csrw    mtvec, t2;
	li      t4, 0x100;
        csrs    medeleg, t4;

	li s1, 1;
        # Get into supervisor mode
        li t4, (1 << 11) | (1 << 5);
        csrw mstatus, t4;
        la t5, OS;
        csrw mepc, t5;
        mret;


.align 2
OS:
        # Enable virtual memory
        li a0, (8 << 60) | PN(PT2_PA);
        csrw satp, a0;
        sfence.vma; # Refetch the SATP register

	la t2, s_trap;
	csrw 		stvec, t2;

        # Set USER_VA->USER_PA
        li t2, PT0_PA + 8*PN0(USER_VA);
        li t3, (PN(USER_PA) << 10) | 0xff;
        sw t3, 0(t2);

        # Set USER_VA_2->USER_PA_2
        li t2, PT0_PA + 8*PN0(USER_VA_2);
        li t3, (PN(USER_PA_2) << 10) | 0xff;
        sw t3, 0(t2);

        # Enable writing to User PTE in S-Mode
        li t0, (1 << 18);
        csrs sstatus, t0;
				
	li  t0, 1;
	beq s1, t0, load_p1;
	li  t0, 2;
	beq s1, t0, load_p2;
        li  t0, 3;
	bge s1, t0, end_program;
load_p1:
        # Load program to user space
        la t0, user_program; # Load the the address to start copying into t0
        la t1, user_program_end # Load the address to stop copying into t1
        li t3, USER_VA; # start of program for copying
        li t5, USER_VA; # which program to jump to for user mode
        csrw    sepc, t5;
1:
        lw t4, 0(t0); # Load a word from the user program
        sw t4, 0(t3); # Store the word to the destination
        addi t0, t0, 4; # Increment the user program address
        addi t3, t3, 4; # Increment the destination address
        blt t0, t1, 1b; # Repeat until the end of the user program is reached
	j to_user;

load_p2:
        # Load program to user space
        la s3, user_program; # Load the the address to start copying into s3
        la s4, user_program_end; # Load the address to stop copying into s4
        li s5, USER_VA_2; # start of program for copying
        li s6, USER_VA_2; # which program to jump to for user mode
        csrw    sepc, s6;
2:
        lw s7, 0(s3); # Load a word from the user program
        sw s7, 0(s5); # Store the word to the destination
        addi s3, s3, 4; # Increment the user program address
        addi s5, s5, 4; # Increment the destination address
        blt s3, s4, 2b; # Repeat until the end of the user program is reached
	j to_user;

end_program:
	ecall; #to m_trap

to_user:
        # Disable writing to User PTE in S-Mode
        li t0, (1 << 18);
        csrc sstatus, t0;

        # Get into user mode
        sret;

m_trap:
	nop;
	ecall; #exit

s_trap:
	addi s1, s1, 1;
	la t0, OS;
	csrw stvec, t0;
	sret;
			

        .data

.align 2
user_program:
        # store 154 at USER_VA+0xf00
        li      t0, 0x154b;
        li      t1, USER_VA+0xf00;
        sw      t0, 0(t1);
        # load 154 to t2
        lw      t2, 0(t1);
        # exit
        li      a0, 0;
        li      a7, 93;
        ecall;
user_program_end:

        .section ".tohost","aw",@progbits
        .globl tohost
        .globl fromhost

        .align 6
tohost: .dword 0
        .align 6
fromhost: .dword 0
