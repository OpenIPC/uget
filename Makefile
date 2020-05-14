CFLAGS=-O3
CROSS_COMPILE=arm-hisiv510-linux-
CC=$(CROSS_COMPILE)gcc
STRIP=$(CROSS_COMPILE)strip

all: uget bin2sh

uget: uget.o
	$(CC) $(CFLAGS) -o $@ $^
	$(STRIP) $@
	upx $@

bin2sh: bin2sh.c
	cc -o $@ $^
