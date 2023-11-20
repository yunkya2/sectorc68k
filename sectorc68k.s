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
;;; d0: scratch register
;;; d1: current token
;;; d2: flag for "tok_is_num"
;;; d3: flags for "tok_is_call", trailing "()"
;;; d4: scratch register
;;; d5: saved token for assigned variable
;;; d6: function token
;;; d7: semi-colon buffer
;;; a0: fn symbol table base address
;;; a1: codegen destination address
;;; a2: forward jump patch location
;;; a3: function address
;;; a4: tok_next
;;; (a6: used for debug)
;;; sp: stack pointer, we don't mess with this
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_entry::
entry:
    lea.l   codegen(pc),a1
    movea.l a1,a0
    adda.l  #$18000,a0

    lea.l   tok_next(pc),a4
    moveq.l #0,d7
    ;; [fall-through]

    ;; main loop for parsing all decls
compile:
    ;; advance to either "int" or "void"
    jsr     (a4)

    ;; if "int" then skip a variable
    cmpi.w  #TOK_INT,d1
    bne     compile_function
    jsr     (a4)                    ; consume "int" and <ident>
    jsr     (a4)
    bra     compile

compile_function:                   ; parse and compile a function decl
    jsr     (a4)                    ; consume "void"
    move.w  d1,d6                   ; save function name token
    movea.l a1,a3                   ; save function address
    add.w   d1,d1                   ; (must be word aligned)
    move.w  a1,(a0,d1.w)            ; record function address in symtbl

    bsr     compile_stmts_tok_next2 ; compile function body
    move.w  #$4e75,(a1)+            ; emit "rts" instruction

    cmpi.w  #TOK_START,d6
    bne     compile                 ; otherwise, loop and compile another declaration
    ;; [fall-through]

    ;; done compiling, execute the binary
execute:
    .ifdef  SCTEST
    rts
    .else
    jsr     (a3)
    .dc.w   $ff00                   ; DOS _EXIT
    .endif

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; compile statements (optionally advancing tokens beforehand)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
_do_call:
    move.w  #$6100,(a1)+            ; emit "bsr" instruction
    add.w   d1,d1                   ; (must be word aligned)
    move.w  (a0,d1.w),d0            ; load function offset from symbol-table
    sub.w   a1,d0                   ; compute relative to this location: "dest - cur"
    move.w  d0,(a1)+                ; emit target
    ;; [fall-through]

compile_stmts_tok_next2:
    jsr     (a4)
compile_stmts_tok_next:
    jsr     (a4)
compile_stmts:
    cmpi.w  #TOK_BLK_END,d1         ; if we reach '}' then return
    beq     return

    tst.b   d3                      ; if d3 is 0, it's not a call
    bne     _do_call

    cmpi.w  #TOK_ASM,d1             ; check for "asm"
    bne     _not_asm
    jsr     (a4)                    ; tok_next to get literal byte
    move.w  d1,(a1)+                ; emit the literal
    bra     compile_stmts_tok_next2 ; loop to compile next statement

_not_asm:
    cmpi.w  #TOK_IF_BEGIN,d1        ; check for "if"
    bne     _not_if
    bsr     _control_flow_block     ; compile control-flow block
    bra     _patch_fwd              ; patch up forward jump of if-stmt

_not_if:
    cmpi.w  #TOK_WHILE_BEGIN,d1     ; check for "while"
    bne     _not_while
    move.w  a1,-(sp)                ; save loop start location
    bsr     _control_flow_block     ; compile control-flow block

_patch_back:                        ; patch up backward and forward jumps of while-stmt
    move.w  #$6000,(a1)+            ; emit "bra" instruction (backwards)
    move.w  (sp)+,d0                ; restore loop start location
    sub.w   a1,d0                   ; compute relative to this location: "dest - cur"
    move.w  d0,(a1)+                ; emit target
    ;; [fall-through]
_patch_fwd:
    move.w  a1,d0                   ; compute relative fwd jump to this location: "dest - src"
    sub.w   a2,d0
    move.w  d0,(a2)                 ; patch forward jump
    bra     compile_stmts_tok_next  ; loop to compile next statement

_control_flow_block:
    bsr     compile_expr_tok_next   ; compile loop or if condition expr

    ;; emit forward jump
    move.l  #$4a406700,(a1)+        ; emit "tst.w d0; beq xxxx"
    move.l  a1,-(sp)                ; save forward patch location
    addq.l  #2,a1                   ; emit placeholder for target
    bsr     compile_stmts_tok_next  ; compile a block of statements
    move.l  (sp)+,a2                ; restore forward patch location

return:                             ; this label gives us a way to do conditional returns
    rts                             ; (e.g. "jne return")

_not_while:
    bsr     compile_assign          ; handle an assignment statement
    bra     compile_stmts           ; loop to compile next statement

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; compile assignment statement
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
_do_deref:
    ;; compile deref (load)
    jsr     (a4)                    ; consume "*(int*)"
    move.w  #$3030,-(sp)            ; code for "move.w (a0,d6.w),d0"
    bra     emit_common_ptr_op      ; [tail-call]

compile_assign:
    cmpi.w  #TOK_DEREF,d1           ; check for "*(int*)"
    bne     _not_deref_store
    jsr     (a4)                    ; consume "*(int*)"
    bsr     save_var_and_compile_expr ; compile rhs first
    ;; [fall-through]

compile_store_deref:
    move.w  d5,d1                   ; restore dest var token
    move.w  #$3180,-(sp)            ; code for "move.w d0,(a0,d6.w)"
    ;; [fall-through]

emit_common_ptr_op:
    move.w  #$3c28,(a1)+            ; emit "move.w imm(a0),d6"
    bsr     emit_var
    move.w  (sp)+,(a1)+             ; emit load/store dereference 
    move.w  #$6000,(a1)+            ; emit addressing word for "(a0,d6.w)"
    rts

_not_deref_store:
    bsr     save_var_and_compile_expr ; compile rhs first
    ;; [fall-through]

compile_store:
    move.w  d5,d1                   ; restore dest var token
    move.w  #$3140,(a1)+            ; code for "move.w d0,imm(a0)"
    bra     emit_var                ; [tail-call]

save_var_and_compile_expr:
    move.w  d1,d5                   ; save dest to bp
    jsr     (a4)                    ; consume dest
    ;; [fall-through]               ; fall-through will consume "=" before compiling expr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; compile expression
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
compile_expr_tok_next:
    jsr     (a4)
compile_expr:
    bsr     compile_unary           ; compile left-hand side

    lea.l   binary_oper_tbl-2(pc),a2 ; load ptr to operator table
    moveq.l #14-1,d4                ; number of the operator table items - 1
_check_next:
    addq.l  #2,a2
    cmp.w   (a2)+,d1                ; matches token?
    dbeq    d4,_check_next
    bne     _not_found              ; all-done, not found

    move.w  (a2),-(sp)              ; load 16-bit of machine-code and save it to the stack
    move.w  #$3f00,(a1)+            ; emit "move.w d0,-(sp)"
    jsr     (a4)                    ; consume operator token
    bsr     compile_unary           ; compile right-hand side
    move.l  #$3400301f,(a1)+        ; emit "move.w d0,d2; move.w (sp)+,d0"

    move.w  (sp)+,d1                ; restore 16-bit of machine-code
    cmpi.b  #$c0,d1                 ; detect the special case for comparison ops
    bne     emit_op             
emit_cmp_op:
    move.w  #$b042,(a1)+            ; emit "cmp.w d2,d0"
    move.w  d1,(a1)+                ; emit machine code for op
    move.w  #$0240,(a1)+            ; emit "andi.w #imm,d0"
    moveq.l #1,d1                   ; imm = 1
    ;; [fall-through]

emit_op:
    move.w  d1,(a1)+                ; emit machine code for op
_not_found:
    rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; compile unary
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
compile_unary:
    cmpi.w  #TOK_DEREF,d1           ; check for "*(int*)"
    beq     _do_deref

    cmpi.w  #TOK_LPAREN,d1          ; check for "("
    bne     _not_paren
    bsr     compile_expr_tok_next   ; consume "(" and compile expr
    jmp     (a4)                    ; [tail-call] to consume ")"

_not_paren:
    cmpi.w  #TOK_ADDR,d1            ; check for "&"
    bne     _not_addr
    jsr     (a4)                    ; consume "&"
    move.w  #$303c,(a1)+            ; code for "move.w #imm,d0"
    bra     emit_var                ; [tail-call] to emit code

_not_addr:
    tst.b   d2                      ; check for tok_is_num
    beq     _not_int
    move.w  #$303c,(a1)+            ; emit "move.w #imm,d0"
    bra     emit_tok                ; [tail-call] to emit imm

_not_int:
    ;; compile var
    move.w  #$3028,(a1)+            ; code for "move.w imm(a0),d0"
    ;; [fall-through]

emit_var:
    add.w   d1,d1                   ; d1 = 2*d1 (scale up for 16-bit)
    ;; [fall-through]

emit_tok:
    move.w  d1,(a1)+                ; emit token value
    ;; [fall-through]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; get next token, setting the following:
;;;   d1: token
;;;   d2: tok_is_num
;;;   d3: tok_is_call
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
tok_next:
    moveq.l #' ',d4
    bsr     getch
    cmp.b   d4,d0                   ; skip spaces (anything <= ' ' is considered space)
    ble     tok_next

    moveq.l #0,d1                   ; zero token reg
    moveq.l #0,d3                   ; zero last-two chars reg

    cmpi.b  #'9',d0
    sle.b   d2                      ; tok_is_num = (d0 <= '9')

_nextch:
    cmp.b   d4,d0
    ble     _done                   ; if char is space then break

    lsl.w   #8,d3
    move.b  d0,d3                   ; shift this char into d3

    .ifndef NOHEX
    cmpi.w  #$3078,d3               ; "0x"
    beq     _nextch16
    .endif

    mulu.w  #10,d1
    subi.w  #'0',d0
    add.w   d0,d1                   ; atoi computation: d1 = 10 * d1 + (d0 - '0')

    bsr     getch
    bra     _nextch                 ; [loop]

    .ifndef NOHEX
_nextch16_1:
    lsl.w   #4,d1
    subi.w  #'0',d0
    cmpi.w  #9,d0
    bls     _nextch16_2
    subi.w  #39,d0
_nextch16_2:
    add.w   d0,d1
    ;; [fall-through]
_nextch16:
    bsr     getch
    cmp.b   d4,d0
    bgt     _nextch16_1             ; if char is space then break
    ;; [fall-through]
    .endif

_done:
    cmpi.w  #$2f2f,d3               ; check for single-line comment "//"
    beq     _comment_double_slash
    cmpi.w  #$2f2a,d3               ; check for multi-line comment "/*"
    beq     _comment_multi_line
    cmpi.w  #$2829,d3               ; check for call parens "()"
    seq.b   d3
    rts

_comment_double_slash:
    bsr     getch                   ; get next char
    cmpi.b  #$0a,d0                 ; check for newline '\n'
    bne     _comment_double_slash   ; [loop]
    jmp     (a4)                    ; [tail-call]

_comment_multi_line:
    jsr     (a4)                    ; get next token
    cmpi.w  #65475,d1               ; check for token "*/"
    bne     _comment_multi_line     ; [loop]
    jmp     (a4)                    ; [tail-call]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; get next char: returned in d0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
getch:
    moveq.l #0,d0
    tst.b   d7                      ; test the semi-colon buffer
    bne     getch_done1

    .ifdef  SCTEST
    .extrn  _source
    movea.l _source,a6
    moveq.l #0,d0
    move.b  (a6)+,d0
    move.l  a6,_source
    .else
    .dc.w   $ff08                   ; DOS _GETC
    .endif

    cmpi.b  #';',d0                 ; check for ';'
    bne     getch_done              ; if not ';' return it

getch_done1:
    exg.l   d0,d7                   ; save the ';' and return 0 instead, treated as whitespace
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
    ;; if the number of items is changed, compile_expr needs to be fixed

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    .even

_codegen::
codegen:
    .ifdef  SCTEST
    .ds.b   65536
    .ds.b   65536
    .endif

    .end
