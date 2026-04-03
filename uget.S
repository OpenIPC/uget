@ uget - minimal HTTP downloader in ARM32 assembly
@ Dynamically linked for gethostbyname + mkstemp only; everything else is raw syscalls.

.syntax unified
.arch armv5te
.arm

@ ---- ARM EABI syscall numbers ----
.equ SYS_exit_group, 248
.equ SYS_fork,       2
.equ SYS_execve,     11
.equ SYS_wait4,      114
.equ SYS_write,      4
.equ SYS_close,      6
.equ SYS_unlink,     10
.equ SYS_fchmod,     94
.equ SYS_socket,     281
.equ SYS_connect,    283
.equ SYS_sendto,     290
.equ SYS_recvfrom,   292

@ ---- constants ----
.equ AF_INET,       2
.equ SOCK_STREAM,   1
.equ STDOUT,        1

@ ---- error codes (match C version) ----
.equ ERR_SOCKET,    2
.equ ERR_DNS,       3
.equ ERR_CONNECT,   4
.equ ERR_SEND,      5
.equ ERR_USAGE,     6

@ ---- stack frame layout ----
@ We use r4-r11 as callee-saved working registers.
@ Frame (allocated below argv on the initial stack):
.equ F_RUN,    0           @ run_program flag (4 bytes)
.equ F_FD,     4           @ write fd (4 bytes)
.equ F_HOST,   8           @ hostname pointer (4 bytes)
.equ F_URI,    12          @ uri pointer (4 bytes)
.equ F_SOCK,   16          @ socket fd (4 bytes)
.equ F_TMP,    20          @ temfname buffer (16 bytes)
.equ F_SIZE,   40          @ total frame size (8-byte aligned for AAPCS)

@ ============================================================
.section .text
.globl _start
.type _start, %function

_start:
        ldr     r0, [sp]                @ argc
        add     r1, sp, #4              @ argv

        @ Allocate frame
        sub     sp, sp, #F_SIZE
        mov     r4, sp                  @ r4 = frame pointer (kept throughout)

        @ if (argc < 2) exit(ERR_USAGE)
        cmp     r0, #2
        blt     .Lusage

        @ Default: run_program=0, url_arg=1
        mov     r2, #0
        str     r2, [r4, #F_RUN]
        mov     r5, #1                  @ url_arg index

        @ Check for "run" mode: argc==3 && argv[1]=="run"
        cmp     r0, #3
        bne     .Lgot_args
        ldr     r0, [r1, #4]            @ argv[1]
        ldr     r2, =str_run
        bl      streq
        cmp     r0, #0
        bne     .Lusage                 @ argc==3 but argv[1]!="run"
        mov     r2, #1
        str     r2, [r4, #F_RUN]
        mov     r5, #2                  @ url_arg=2
.Lgot_args:

        @ Load hostname = argv[url_arg]
        add     r0, r4, #F_SIZE         @ back to original sp
        add     r0, r0, #4              @ &argv[0]
        ldr     r6, [r0, r5, lsl #2]    @ r6 = hostname

        @ Split at first '/' -> hostname + uri
        mov     r0, #0
        str     r0, [r4, #F_URI]        @ uri = NULL
        mov     r0, r6
1:      ldrb    r1, [r0]
        cmp     r1, #0
        beq     2f
        cmp     r1, #'/'
        bne     3f
        mov     r1, #0
        strb    r1, [r0]
        add     r1, r0, #1
        str     r1, [r4, #F_URI]
        b       2f
3:      add     r0, r0, #1
        b       1b
2:
        str     r6, [r4, #F_HOST]

        @ fd = STDOUT
        mov     r0, #STDOUT
        str     r0, [r4, #F_FD]

        @ if (run_program) fd = mkstemp(temfname)
        ldr     r0, [r4, #F_RUN]
        cmp     r0, #0
        beq     .Ldo_download

        @ Copy template to stack frame
        ldr     r1, =str_tmptemplate
        add     r0, r4, #F_TMP
        bl      strcopy
        mov     r2, #0
        strb    r2, [r0]                @ NUL terminate

        add     r0, r4, #F_TMP
        bl      mkstemp(PLT)
        str     r0, [r4, #F_FD]

@ ================ download ================
.Ldo_download:
        @ gethostbyname(hostname)
        ldr     r0, [r4, #F_HOST]
        bl      gethostbyname(PLT)
        cmp     r0, #0
        beq     .Lerr_dns
        mov     r5, r0                  @ r5 = hostent*

        @ socket(AF_INET, SOCK_STREAM, 0)
        mov     r0, #AF_INET
        mov     r1, #SOCK_STREAM
        mov     r2, #0
        ldr     r7, =SYS_socket
        svc     #0
        cmp     r0, #0
        blt     .Lerr_socket
        str     r0, [r4, #F_SOCK]
        mov     r6, r0                  @ r6 = sockfd

        @ Build sockaddr_in on stack
        sub     sp, sp, #16
        mov     r0, #0
        str     r0, [sp]
        str     r0, [sp, #4]
        str     r0, [sp, #8]
        str     r0, [sp, #12]
        mov     r0, #AF_INET
        strh    r0, [sp]                @ sin_family
        mov     r0, #0x5000             @ htons(80) on little-endian = 0x5000
        strh    r0, [sp, #2]            @ sin_port
        ldr     r0, [r5, #16]           @ he->h_addr_list
        ldr     r0, [r0]                @ h_addr_list[0]
        ldr     r0, [r0]                @ *(uint32_t*)
        str     r0, [sp, #4]            @ sin_addr

        @ connect(sockfd, &addr, 16)
        mov     r0, r6
        mov     r1, sp
        mov     r2, #16
        ldr     r7, =SYS_connect
        svc     #0
        add     sp, sp, #16
        cmp     r0, #0
        blt     .Lerr_connect

        @ ---- Build HTTP request ----
        @ Use a 1024-byte buffer (enough for HTTP request)
        sub     sp, sp, #1024
        mov     r0, sp

        ldr     r1, =str_get
        bl      strcopy                 @ "GET /"
        ldr     r1, [r4, #F_URI]
        cmp     r1, #0
        blne    strcopy                 @ uri
        ldr     r1, =str_http
        bl      strcopy                 @ " HTTP/1.0\r\nHost: "
        ldr     r1, [r4, #F_HOST]
        bl      strcopy                 @ hostname
        ldr     r1, =str_crlf2
        bl      strcopy                 @ "\r\n\r\n"

        @ sendto(sockfd, buf, len, 0, NULL, 0)
        sub     r5, r0, sp              @ r5 = tosent
        mov     r0, r6                  @ sockfd
        mov     r1, sp                  @ buf
        mov     r2, r5                  @ len
        mov     r3, #0                  @ flags
        push    {r4, r5}               @ save frame ptr + tosent; also push 2 vals for sendto args 5,6
        mov     r4, #0                  @ dest_addr = NULL
        mov     r5, #0                  @ addrlen = 0
        ldr     r7, =SYS_sendto
        svc     #0
        mov     r8, r0                  @ r8 = nsent
        pop     {r4, r5}               @ restore frame ptr + tosent
        add     sp, sp, #1024           @ free request buffer

        cmp     r8, r5
        bne     .Lerr_send

        @ ---- Receive loop ----
        @ r6 = sockfd (still valid)
        @ Allocate recv buffer
        sub     sp, sp, #4096
        mov     r8, #1                  @ r8 = header flag

.Lrecv_loop:
        @ recvfrom(sockfd, buf, 4096, 0, NULL, 0)
        mov     r0, r6
        mov     r1, sp
        mov     r2, #4096
        mov     r3, #0
        push    {r4, r5}
        mov     r4, #0
        mov     r5, #0
        ldr     r7, =SYS_recvfrom
        svc     #0
        pop     {r4, r5}

        cmp     r0, #0
        ble     .Lrecv_done

        mov     r9, r0                  @ r9 = nrecvd
        mov     r10, sp                 @ r10 = ptr (start of data to write)

        cmp     r8, #0
        beq     .Lwrite_body

        @ --- header mode: find "\r\n\r\n" ---
        mov     r0, sp
        mov     r1, r9
        bl      find_hdr_end
        cmp     r0, #0
        beq     .Lrecv_loop             @ header end not found yet

        @ r0 = ptr to "\r\n\r\n"
        mov     r10, r0                 @ save ptr

        @ Parse HTTP status code from buffer start
        mov     r0, sp
        bl      parse_status            @ r0 = HTTP status code (e.g. 200, 404)
        mov     r11, r0

        @ if (code / 100 != 2) -> error exit
        mov     r1, #100
        bl      divmod                  @ r0 = code/100, r1 = code%100
        cmp     r0, #2
        bne     .Lhttp_error

        @ header = 0, advance ptr past "\r\n\r\n"
        mov     r8, #0
        add     r10, r10, #4            @ skip \r\n\r\n
        @ nrecvd -= (ptr - buf)
        sub     r1, r10, sp
        sub     r9, r9, r1

.Lwrite_body:
        cmp     r9, #0
        ble     .Lrecv_loop
        ldr     r0, [r4, #F_FD]
        mov     r1, r10
        mov     r2, r9
        mov     r7, #SYS_write
        svc     #0
        b       .Lrecv_loop

.Lrecv_done:
        add     sp, sp, #4096
        mov     r0, #0
        b       .Lcleanup

.Lhttp_error:
        @ Compress HTTP code: exit = (code/100)*10 + code%10
        @ r11 = original code, r0 = code/100
        add     sp, sp, #4096
        mov     r10, r0                 @ r10 = code/100 (divmod clobbers r2)
        mov     r0, r11                 @ restore full code
        mov     r1, #10
        bl      divmod                  @ r0 = code/10, r1 = code%10
        add     r0, r1, r10, lsl #3    @ r1 + (code/100)*8
        add     r0, r0, r10, lsl #1    @ + (code/100)*2 = r1 + (code/100)*10
        b       .Lcleanup

@ ---- cleanup and exit ----
.Lerr_dns:      mov     r0, #ERR_DNS
                b       .Lcleanup
.Lerr_socket:   mov     r0, #ERR_SOCKET
                b       .Lcleanup
.Lerr_connect:  mov     r0, #ERR_CONNECT
                b       .Lcleanup
.Lerr_send:     add     sp, sp, #0      @ (buffer already freed above)
                mov     r0, #ERR_SEND
                b       .Lcleanup
.Lusage:        mov     r0, #ERR_USAGE
                b       .Lexit

.Lcleanup:
        mov     r5, r0                  @ r5 = return code
        cmp     r5, #0
        bne     .Lcleanup_unlink

        @ if (!run_program) just exit
        ldr     r0, [r4, #F_RUN]
        cmp     r0, #0
        beq     .Lcleanup_exit

        @ fchmod(fd, S_IRUSR|S_IXUSR)
        ldr     r0, [r4, #F_FD]
        ldr     r1, =0x140              @ S_IRUSR|S_IXUSR = 0x100|0x40
        mov     r7, #SYS_fchmod
        svc     #0

        @ close(fd)
        ldr     r0, [r4, #F_FD]
        mov     r7, #SYS_close
        svc     #0

        @ fork()
        mov     r7, #SYS_fork
        svc     #0
        cmp     r0, #0
        beq     .Lchild

        @ Parent: wait4(child, &wstatus, 0, NULL)
        sub     sp, sp, #4              @ space for wstatus
        mov     r1, sp                  @ &wstatus
        mov     r2, #0                  @ options
        mov     r3, #0                  @ rusage
        mov     r7, #SYS_wait4
        svc     #0
        ldr     r5, [sp]                @ wstatus
        add     sp, sp, #4
        @ WEXITSTATUS = (wstatus >> 8) & 0xff
        mov     r5, r5, lsr #8
        and     r5, r5, #0xff
        b       .Lcleanup_unlink

.Lchild:
        @ execve(temfname, {temfname, NULL}, NULL)
        add     r0, r4, #F_TMP         @ filename
        sub     sp, sp, #8
        str     r0, [sp]               @ argv[0] = temfname
        mov     r1, #0
        str     r1, [sp, #4]           @ argv[1] = NULL
        mov     r1, sp                  @ argv
        mov     r2, #0                  @ envp = NULL
        mov     r7, #SYS_execve
        svc     #0
        @ If execve returns, exit with failure
        mov     r0, #1
        mov     r7, #SYS_exit_group
        svc     #0

.Lcleanup_unlink:
        ldr     r0, [r4, #F_RUN]
        cmp     r0, #0
        beq     .Lcleanup_exit
        add     r0, r4, #F_TMP
        mov     r7, #SYS_unlink
        svc     #0

.Lcleanup_exit:
        mov     r0, r5
.Lexit:
        mov     r7, #SYS_exit_group
        svc     #0

@ ============================================================
@ Helper functions
@ ============================================================

@ streq(r0=s1, r1=s2) -> r0=0 if equal, r0=1 if not
@ Clobbers: r2, r3
streq:
1:      ldrb    r2, [r0], #1
        ldrb    r3, [r1], #1
        cmp     r2, r3
        bne     2f
        cmp     r2, #0
        bne     1b
        mov     r0, #0
        bx      lr
2:      mov     r0, #1
        bx      lr

@ strcopy(r0=dst, r1=src) -> r0=end of dst (past last char, no NUL)
@ Clobbers: r2
strcopy:
1:      ldrb    r2, [r1], #1
        cmp     r2, #0
        bxeq    lr
        strb    r2, [r0], #1
        b       1b

@ find_hdr_end(r0=buf, r1=len) -> r0=ptr to "\r\n\r\n" or 0
@ Clobbers: r1, r2
find_hdr_end:
        add     r1, r0, r1
        sub     r1, r1, #3
1:      cmp     r0, r1
        bge     2f
        ldrb    r2, [r0]
        cmp     r2, #0x0d
        bne     3f
        ldrb    r2, [r0, #1]
        cmp     r2, #0x0a
        bne     3f
        ldrb    r2, [r0, #2]
        cmp     r2, #0x0d
        bne     3f
        ldrb    r2, [r0, #3]
        cmp     r2, #0x0a
        bxeq    lr
3:      add     r0, r0, #1
        b       1b
2:      mov     r0, #0
        bx      lr

@ parse_status(r0=buf) -> r0=HTTP status code
@ Parses "HTTP/x.y NNN ..." -> NNN
@ Clobbers: r1, r2
parse_status:
1:      ldrb    r1, [r0], #1
        cmp     r1, #0
        bxeq    lr
        cmp     r1, #' '
        bne     1b
2:      ldrb    r1, [r0], #1            @ skip spaces
        cmp     r1, #' '
        beq     2b
        sub     r0, r0, #1
        @ Parse up to 3 digits
        mov     r2, #0
        ldrb    r1, [r0], #1
        sub     r1, r1, #'0'
        cmp     r1, #9
        bhi     3f
        add     r2, r2, r1
        ldrb    r1, [r0], #1
        sub     r1, r1, #'0'
        cmp     r1, #9
        bhi     3f
        add     r2, r2, r2, lsl #2     @ r2 *= 5
        add     r2, r1, r2, lsl #1     @ r2 = r2*10 + digit (via r2*5*2)
        ldrb    r1, [r0], #1
        sub     r1, r1, #'0'
        cmp     r1, #9
        bhi     3f
        add     r2, r2, r2, lsl #2
        add     r2, r1, r2, lsl #1
3:      mov     r0, r2
        bx      lr

@ divmod(r0=dividend, r1=divisor) -> r0=quotient, r1=remainder
@ Simple restoring division for small values
@ Clobbers: r2, r3
divmod:
        mov     r2, #0                  @ quotient
1:      cmp     r0, r1
        blt     2f
        sub     r0, r0, r1
        add     r2, r2, #1
        b       1b
2:      mov     r1, r0                  @ remainder
        mov     r0, r2                  @ quotient
        bx      lr

@ ============================================================
@ Read-only data
@ ============================================================
.section .rodata
str_run:         .asciz "run"
str_tmptemplate: .asciz "/tmp/ugetXXXXXX"
str_get:         .asciz "GET /"
str_http:        .ascii " HTTP/1.0\r\nHost: "
                 .byte 0
str_crlf2:       .ascii "\r\n\r\n"
                 .byte 0
