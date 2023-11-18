#include <stdio.h>

const char *src = "\
void puta()
{
    asm 29249;
    asm 28704;
    asm 20047;
}

int i;
void _start()
{
    i = 0;
    while( i < 10 ){
        puta();
        i = i + 1;
    }
}
";

const char *source;
void entry();

int main()
{
    source = src;

    entry();

    return 0;
}
