CFLAGS=-Os
CROSS_COMPILE?=arm-hisiv510-linux-
CC=$(CROSS_COMPILE)gcc
STRIP=$(CROSS_COMPILE)strip

BINARIES=uget bin2sh

all: $(BINARIES)

uget: uget.o
	$(CC) $(CFLAGS) -o $@ $^
	$(STRIP) -R .comment -R .note -R .note.ABI-tag $@
	upx $@

bin2sh: bin2sh.c
	cc -o $@ $^

clean:
	-rm -f uget $(BINARIES) *.o
