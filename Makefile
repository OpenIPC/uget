CFLAGS=-Os -ffunction-sections -fdata-sections
LDFLAGS=-Wl,--gc-sections
CROSS_COMPILE?=arm-hisiv510-linux-
CC=$(CROSS_COMPILE)gcc
STRIP=$(CROSS_COMPILE)strip
STRIP_FLAGS=-R .comment -R .note -R .note.ABI-tag -R .eh_frame -R .eh_frame_hdr -R .ARM.attributes -R .jcr

BINARIES=uget uget-asm bin2sh

all: $(BINARIES)

uget: uget.o
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	$(STRIP) $(STRIP_FLAGS) $@
	-upx $@

uget-asm: uget.S
	$(CC) -c -o uget-asm.o $^
	$(CC) -nostartfiles -o $@ uget-asm.o -lc
	$(STRIP) $(STRIP_FLAGS) $@
	-upx $@

bin2sh: bin2sh.c
	cc -o $@ $^

clean:
	-rm -f $(BINARIES) *.o
