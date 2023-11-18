int div10_unsigned_n;
int div10_unsigned_q;
int div10_unsigned_r;
void div10_unsigned()
{
  /* Taken from "Hacker's Delight", modified to "fit your screen" */

  tmp1 = ( div10_unsigned_n >> 1 ) & 32767; // unsigned
  tmp2 = ( div10_unsigned_n >> 2 ) & 16383; // unsigned
  div10_unsigned_q = tmp1 + tmp2;

  tmp1 = ( div10_unsigned_q >> 4 ) & 4095; // unsigned
  div10_unsigned_q = div10_unsigned_q + tmp1;

  tmp1 = ( div10_unsigned_q >> 8 ) & 255; // unsigned
  div10_unsigned_q = div10_unsigned_q + tmp1;

  div10_unsigned_q = ( div10_unsigned_q >> 3 ) & 8191; // unsigned

  div10_unsigned_r = div10_unsigned_n
    - ( ( div10_unsigned_q << 3 ) + ( div10_unsigned_q << 1 ) );

  if( div10_unsigned_r > 9 ){
    div10_unsigned_q = div10_unsigned_q + 1;
    div10_unsigned_r = div10_unsigned_r - 10;
  }
}

int print_ch;
void print_char()
{
    print_ch = print_ch;
    asm 0x3f00;             // move.w d0,-(sp)
    asm 0xff02;             // DOS _PUTCHAR
    asm 0x548f;             // addq.l #2,sp
}

void print_newline()
{
    print_ch = 10;
    print_char();
    print_ch = 13;
    print_char();
}

int print_num; // input
int print_u16_bufptr;
int print_u16_cur;
void print_u16()
{
  print_u16_bufptr = 30000; // buffer for ascii digits

  if( print_num == 0 ){
    print_ch = 48;
    print_char();
  }

  print_u16_cur = print_num;
  while( print_u16_cur != 0 ){
    div10_unsigned_n = print_u16_cur;
    div10_unsigned();

    *(int*) print_u16_bufptr = div10_unsigned_r;
    print_u16_bufptr = print_u16_bufptr + 2;

    print_u16_cur = div10_unsigned_q;
  }

  while( print_u16_bufptr != 30000 ){ // emit them in reverse over
    print_u16_bufptr = print_u16_bufptr - 2;
    print_ch = ( *(int*) print_u16_bufptr & 255 ) + 48;
    print_char();
  }
}

// uses 'print_num' and 'print_ch'
void print_i16()
{
  if( print_num < 0 ){
    print_ch = 45; print_char(); // '-'
    print_num = 0 - print_num;
  }
  print_u16();
}

void b_super()
{
  asm 0x93c9;       // suba.l a1,a1
  asm 0x7081;       // moveq.l #$81,d0
  asm 0x4e4f;       // trap #15
}

void graph_init()
{
  asm 0x7206;       // moveq.l #$06,d1
  asm 0x7010;       // moveq.l #$10,d0
  asm 0x4e4f;       // trap #15
  asm 0x7090;       // moveq.l #$90,d0
  asm 0x4e4f;       // trap #15

  clear_page = 0x0f;
  pixel_page = 0xc0;
  view_page = 0x2f;
}

void wait_vsync()
{
  asm 0x43f9; asm 0x00e8; asm 0x8001; // lea.l $e88001,a1
  asm 0x1011;               // move.b (a1),d0
  asm 0x0200; asm 0x0010;   // andi.b #$10,d0
  asm 0x67f8;               // beq
  asm 0x1011;               // move.b (a1),d0
  asm 0x0200; asm 0x0010;   // andi.b #$10,d0
  asm 0x66f8;               // bne
}

int clear_page;
void graph_clear()
{
  asm 0x43f9; asm 0x00e8; asm 0x0000; // lea.l $e80000,a1
  clear_page = clear_page;
  asm 0x3340; asm 0x002a;             // move.w d0,$002a(a1)
  asm 0x337c; asm 0x0002; asm 0x0480; // move.w #$2,$0480(a1)
}

int view_page;
void graph_vpage()
{
  view_page = view_page;
  asm 0x43f9; asm 0x00e8; asm 0x2600; // lea.l $e82600,a1
  asm 0x3280;               // move.w d0,(a1)
}

int pixel_x;
int pixel_y;
int pixel_color;
int pixel_page;
void graph_set_pixel()
{
  pixel_y = pixel_y;
  asm 0x7e00;       // moveq.l #0,d7
  asm 0x3e00;       // move.w d0,d7
  asm 0xe18f;       // lsl.l #8,d7
  asm 0xe58f;       // lsl.l #2,d7

  pixel_page = pixel_page;
  asm 0x4840;       // swap.w d0
  asm 0x4240;       // clr.w d0
  asm 0x2240;       // movea.l d0,a1
  pixel_x = pixel_x;
  asm 0xd2c0; asm 0xd2c0;   // adda.w d0,a1; adda.w d0,a1
  asm 0xd3c7;               // adda.l d7,a1

  pixel_color = pixel_color;
  asm 0x3280;               // move.w d0,(a1)
}
