;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Token values as computed by the tokenizer's
;;; atoi() calculation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
TOK_INT             equ     6388
TOK_VOID            equ     11386
TOK_ASM             equ     5631
TOK_COMM            equ     65532
TOK_SEMI            equ     11
TOK_LPAREN          equ     65528
TOK_RPAREN          equ     65529
TOK_START           equ     20697
TOK_DEREF           equ     64653
TOK_WHILE_BEGIN     equ     55810
TOK_IF_BEGIN        equ     6232
TOK_BODY_BEGIN      equ     5
TOK_BLK_BEGIN       equ     75
TOK_BLK_END         equ     77
TOK_ASSIGN          equ     13
TOK_ADDR            equ     65526
TOK_SUB             equ     65533
TOK_ADD             equ     65531
TOK_MUL             equ     65530
TOK_AND             equ     65526
TOK_OR              equ     76
TOK_XOR             equ     46
TOK_SHL             equ     132
TOK_SHR             equ     154
TOK_EQ              equ     143
TOK_NE              equ     65399
TOK_LT              equ     12
TOK_GT              equ     14
TOK_LE              equ     133
TOK_GE              equ     153

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Common register uses
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; d0  ax: current token / scratch register / emit val for stosw
;;; d1  bx: current token
;;; d2  dl: flag for "tok_is_num"
;;; d3  dh: flags for "tok_is_call", trailing "()"
;;; d4  di: codegen destination offset
;;; d5  bp: saved token for assigned variable
;;; d6  si: used with lodsw for table scans
;;; d7      semi-colon buffer
;;; sp  sp: stack pointer, we don't mess with this
;;; a0  ds: fn symbol table segment (occasionally set to "cs" to access binary_oper_tbl)
;;; a1  es: codegen destination segment
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_entry::
entry:
    lea.l   codegen(pc),a1
    adda.l  #$8000,a1
    movea.l a1,a0
    adda.l  #$10000,a0

    move.w  #$8000,d4
    moveq.l #0,d7
  ;; [fall-through]

  ;; main loop for parsing all decls
compile:
  ;; advance to either "int" or "void"
    bsr     tok_next

  ;; if "int" then skip a variable
    cmpi.w  #TOK_INT,d0
    bne     compile_function
    bsr     tok_next2           ; consume "int" and <ident>
    bra     compile

compile_function:              ; parse and compile a function decl
    bsr     tok_next            ; consume "void"
    move.w  d1,-(sp)            ; save function name token
    add.w   d1,d1               ; (must be word aligned)
    move.w  d4,(a0,d1.w)        ; record function address in symtbl
    bsr     compile_stmts_tok_next2 ; compile function body

    move.w  #$4e75,(a1,d4.w)    ; emit "rts" instruction
    addq.w  #2,d4

    move.w  (sp)+,d1            ; if the function is _start(), we're done
    cmpi.w  #TOK_START,d1
    bne     compile             ; otherwise, loop and compile another declaration
  ;; [fall-through]

  ;; done compiling, execute the binary
    .ifdef  SCTEST
    rts
    .else
execute:
    add.w   d1,d1               ; (must be word aligned)
    move.w  (a0,d1.w),d1        ; push the offset to "_start()"
    jsr     (a1,d1.w)
    .dc.w   $ff00
    .endif

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; compile statements (optionally advancing tokens beforehand)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
compile_stmts_tok_next2:
    bsr     tok_next
compile_stmts_tok_next:
    bsr     tok_next
compile_stmts:
    move.w  d1,d0
    cmpi.w  #TOK_BLK_END,d0     ; if we reach '}' then return
    beq     return

    tst.b   d3                  ; if dh is 0, it's not a call
    beq     _not_call
    move.w  #$6100,(a1,d4.w)    ; emit "bsr" instruction
    addq.w  #2,d4

    add.w   d1,d1               ; (must be word aligned)
    move.w  (a0,d1.w),d0        ; load function offset from symbol-table
    sub.w   d4,d0               ; compute relative to this location: "dest - cur"
    move.w  d0,(a1,d4.w)        ; emit target
    addq.w  #2,d4

    bra     compile_stmts_tok_next2 ; loop to compile next statement

_not_call:
    cmpi.w  #TOK_ASM,d0         ; check for "asm"
    bne     _not_asm
    bsr     tok_next            ; tok_next to get literal byte
    move.w  d0,(a1,d4.w)        ; emit the literal
    addq.w  #2,d4
    bra     compile_stmts_tok_next2 ; loop to compile next statement

_not_asm:
    cmpi.w  #TOK_IF_BEGIN,d0    ; check for "if"
    bne     _not_if
    bsr     _control_flow_block ; compile control-flow block
    bra     _patch_fwd          ; patch up forward jump of if-stmt

_not_if:
    cmpi.w  #TOK_WHILE_BEGIN,d0 ; check for "while"
    bne     _not_while
    move.w  d4,-(sp)            ; save loop start location
    bsr     _control_flow_block ; compile control-flow block
    bra     _patch_back         ; patch up backward and forward jumps of while-stmt

_not_while:
    bsr     compile_assign      ; handle an assignment statement
    bra     compile_stmts       ; loop to compile next statement

_patch_back:
    move.w  #$6000,(a1,d4.w)    ; emit "bra" instruction (backwards)
    addq.w  #2,d4
    move.w  (sp)+,d0            ; restore loop start location
    sub.w   d4,d0               ; compute relative to this location: "dest - cur"
    move.w  d0,(a1,d4.w)        ; emit target
    addq.w  #2,d4
  ;; [fall-through]
_patch_fwd:
    move.w  d4,d0               ; compute relative fwd jump to this location: "dest - src"
    sub.w   d6,d0
    addq.w  #2,d0
    move.w  d0,-2(a1,d6.w)      ; patch "src - 2"
    bra     compile_stmts_tok_next  ; loop to compile next statement

_control_flow_block:
    bsr     compile_expr_tok_next   ; compile loop or if condition expr

  ;; emit forward jump
    move.l  #$4a406700,(a1,d4.w)    ; emit "tst.w d0; beq xxxx"
    addq.w  #6,d4               ; emit placeholder for target

    move.w  d4,-(sp)            ; save forward patch location
    bsr     compile_stmts_tok_next  ; compile a block of statements
    move.w  (sp)+,d6            ; restore forward patch location

return:                         ; this label gives us a way to do conditional returns
    rts                         ; (e.g. "jne return")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; compile assignment statement
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
compile_assign:
    cmpi.w  #TOK_DEREF,d0       ; check for "*(int*)"
    bne     _not_deref_store
    bsr     tok_next            ; consome "*(int*)"
    bsr     save_var_and_compile_expr ; compile rhs first
  ;; [fall-through]

compile_store_deref:
    move.w  d5,d1               ; restore dest var token
    move.w  #$3180,d0           ; code for "move.w d0,(a0,d6.w)"
  ;; [fall-through]

emit_common_ptr_op:
    move.w  d0,-(sp)
    move.w  #$3c28,d0           ; emit "move.w imm(a0),d6"
    bsr     emit_var
    move.w  (sp)+,(a1,d4.w)     ; emit
    move.w  #$6000,2(a1,d4.w)   ; emit
    addq.w  #4,d4
    rts

_not_deref_store:
    bsr     save_var_and_compile_expr ; compile rhs first
  ;; [fall-through]

compile_store:
    move.w  d5,d1               ; restore dest var token
    move.w  #$3140,d0           ; code for "move.w d0,imm(a0)"
    bra     emit_var            ; [tail-call]

save_var_and_compile_expr:
    move.w  d1,d5               ; save dest to bp
    bsr     tok_next            ; consume dest
  ;; [fall-through]             ; fall-through will consume "=" before compiling expr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; compile expression
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
compile_expr_tok_next:
    bsr     tok_next
compile_expr:
    bsr     compile_unary       ; compile left-hand side

    lea.l   binary_oper_tbl(pc),a2  ; load ptr to operator table
_check_next:
    cmp.w   (a2),d1             ; matches token?
    beq     _found
    tst.w   (a2)                ; end of table?
    addq.l  #4,a2
    bne     _check_next

    rts                         ; all-done, not found

_found:
    move.w  2(a2),-(sp)         ; load 16-bit of machine-code and save it to the stack
    move.w  #$3f00,(a1,d4.w)    ; emit "move.w d0,-(sp)"
    addq.w  #2,d4
    bsr     tok_next            ; consume operator token
    bsr     compile_unary       ; compile right-hand side
    move.l  #$3400301f,(a1,d4.w)    ; emit "move.w d0,d2; move.w (sp)+,d0"
    addq.w  #4,d4

    move.w  (sp)+,d1            ; restore 16-bit of machine-code
    cmpi.b  #$c0,d1             ; detect the special case for comparison ops
    bne     emit_op             
emit_cmp_op:
    move.w  #$b042,(a1,d4.w)    ; emit "cmp.w d2,d0"
    move.w  d1,2(a1,d4.w)       ; emit machine code for op
    move.w  #$0240,4(a1,d4.w)   ; emit "andi.w #imm,d0"
    addq.w  #6,d4
    moveq.l #1,d1               ; imm = 1
  ;; [fall-through]

emit_op:
    move.w  d1,(a1,d4.w)        ; emit machine code for op
    addq.w  #2,d4
    rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; compile unary
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
compile_unary:
    cmpi.w  #TOK_DEREF,d0       ; check for "*(int*)"
    bne     _not_deref
  ;; compile deref (load)
    bsr     tok_next            ; consume "*(int*)"
    move.w  #$3030,d0           ; code for "move.w (a0,d6.w),d0"
    bra     emit_common_ptr_op  ; [tail-call]

_not_deref:
    cmpi.w  #TOK_LPAREN,d0      ; check for "("
    bne     _not_paren
    bsr     compile_expr_tok_next   ; consume "(" and compile expr
    bra     tok_next            ; [tail-call] to consume ")"

_not_paren:
    cmpi.w  #TOK_ADDR,d0        ; check for "&"
    bne     _not_addr
    bsr     tok_next            ; consume "&"
    move.w  #$303c,d0           ; code for "move.w #imm,d0"
    bra     emit_var            ; [tail-call] to emit code

_not_addr:
    tst.b   d2                  ; check for tok_is_num
    beq     _not_int
    move.w  #$303c,(a1,d4.w)    ; emit "move.w #imm,d0"
    addq.w  #2,d4
    bra     emit_tok                  ; [tail-call] to emit imm

_not_int:
  ;; compile var
    move.w  #$3028,d0           ; code for "move.w imm(a0),d0"
  ;; [fall-through]

emit_var:
    move.w  d0,(a1,d4.w)        ; emit
    addq.w  #2,d4
    add.w   d1,d1               ; bx = 2*bx (scale up for 16-bit)
  ;; [fall-through]

emit_tok:
    move.w  d1,(a1,d4.w)        ; emit token value
    addq.w  #2,d4
    bra     tok_next            ; [tail-call]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; get next token, setting the following:
;;;   ax: token             d0
;;;   bx: token             d1
;;;   dl: tok_is_num        d2
;;;   dh: tok_is_call       d3
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
tok_next2:
    bsr     tok_next
    ;; [fall-through]
tok_next:
    bsr     getch
    cmpi.b  #' ',d0             ; skip spaces (anything <= ' ' is considered space)
    ble     tok_next

    moveq.l #0,d1               ; zero token reg
    moveq.l #0,d3               ; zero last-two chars reg

    cmpi.b  #'9',d0
    sle.b   d2                  ; tok_is_num = (al <= '9')

_nextch:
    cmpi.b  #' ',d0
    ble     _done               ; if char is space then break

    lsl.w   #8,d3
    move.b  d0,d3               ; shift this char into d3

    cmpi.w  #$3078,d3           ; "0x"
    beq     _nextch16

    mulu.w  #10,d1
    subi.w  #'0',d0
    add.w   d0,d1               ; atoi computation: d1 = 10 * d1 + (d0 - '0')

    bsr     getch
    bra     _nextch             ; [loop]

_nextch16:
    bsr     getch
    cmpi.b  #' ',d0
    ble     _done               ; if char is space then break

    lsl.w   #4,d1
    subi.w  #'0',d0
    cmpi.w  #9,d0
    bhi     _nextch16_2
    add.w   d0,d1
    bra     _nextch16           ; [loop]
_nextch16_2
    subi.w  #39,d0
    add.w   d0,d1
    bra     _nextch16           ; [loop]

_done:
    move.w  d3,d0
    cmpi.w  #$2f2f,d0           ; check for single-line comment "//"
    beq     _comment_double_slash
    cmpi.w  #$2f2a,d0           ; check for multi-line comment "/*"
    beq     _comment_multi_line
    cmpi.w  #$2829,d0           ; check for call parens "()"
    seq.b   d3

    move.w  d1,d0               ; return token in d0 also
    rts

_comment_double_slash:
    bsr     getch               ; get next char
    cmpi.b  #$0a,d0             ; check for newline '\n'
    bne     _comment_double_slash   ; [loop]
    bra     tok_next            ; [tail-call]

_comment_multi_line:
    bsr     tok_next            ; get next token
    cmpi.w  #65475,d0           ; check for token "*/"
    bne     _comment_multi_line ; [loop]
    bra     tok_next            ; [tail-call]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; get next char: returned in ax (ah == 0, al == ch)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
getch:
    move.b  d7,d0               ; load the semi-colon buffer
    eor.b   d0,d7               ; zero the buffer
    cmpi.b  #';',d0             ; check for ';'
    beq     getch_done          ; if ';' return it

getch_tryagain:
    .ifdef  SCTEST
    .extrn  _source
    movea.l _source,a4
    moveq.l #0,d0
    move.b  (a4)+,d0
    move.l  a4,_source
    .else
    .dc.w   $ff08               ; DOS _GETC
    .endif

    cmpi.b  #';',d0             ; check for ';'
    bne     getch_done          ; if not ';' return it
    move.b  d0,d7               ; save the ';'
    moveq.l #0,d0               ; return 0 instead, treated as whitespace

getch_done:
    rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; binary operator table
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
binary_oper_tbl:
    .dc.w   TOK_ADD,$d042       ; add.w d2,d0
    .dc.w   TOK_SUB,$9042       ; sub.w d2,d0
    .dc.w   TOK_MUL,$c1c2       ; muls.w d2,d0
    .dc.w   TOK_AND,$c042       ; and.w d2,d0
    .dc.w   TOK_OR,$8042        ; or.w d2,d0
    .dc.w   TOK_XOR,$b540       ; eor.w d2,d0
    .dc.w   TOK_SHL,$e568       ; lsl.w d2,d0
    .dc.w   TOK_SHR,$e468       ; lsr.w d2,d0
    .dc.w   TOK_EQ,$57c0        ; seq d0
    .dc.w   TOK_NE,$56c0        ; sne d0
    .dc.w   TOK_LT,$5dc0        ; slt d0
    .dc.w   TOK_GT,$5ec0        ; sgt d0
    .dc.w   TOK_LE,$5fc0        ; sle d0
    .dc.w   TOK_GE,$5cc0        ; sge d0
    .dc.w   0                   ; [sentinel]


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    .even

_codegen::
codegen:
    .ifdef  SCTEST
    .ds.b   65536
    .ds.b   65536
    .endif

    .end
