BINDIR=build
SRC=sectorc68k.s
TARGET=$(BINDIR)/$(SRC:.s=.r)
TARGETX=$(BINDIR)/$(SRC:.s=.x)
OBJ=$(BINDIR)/$(SRC:.s=.o)

SSRC=sctest.c
STARGET=$(BINDIR)/$(SSRC:.c=.x)
SOBJ=$(BINDIR)/$(SSRC:.c=.o)

all: $(TARGET) $(STARGET)

$(TARGET): $(TARGETX)
	cv /r $^ $@

$(TARGETX): $(OBJ)
	lk -o $@ $^

$(OBJ): $(SRC) $(BINDIR)
	as -d -p $(@:.o=.prn) -o $@ $<

$(BINDIR):
	mkdir $(BINDIR)

$(STARGET): $(SOBJ) $(BINDIR)/sc68k.o
	gcc -o $@ $^

$(SOBJ): $(SSRC) $(BINDIR)
	gcc -O -c -o $@ $<

$(BINDIR)/sc68k.o: $(SRC) $(BINDIR)
	as -d -s SCTEST -o $@ $<

clean:
	rm -rf build 

.PHONY: clean
