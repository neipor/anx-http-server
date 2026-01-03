# Makefile for Pure Assembly Project

AS = as
LD = ld
ASFLAGS = -g
LDFLAGS = -static

TARGET = anx_asm_demo
SRCS = src/server.s
OBJS = $(SRCS:.s=.o)

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $^

%.o: %.s
	$(AS) $(ASFLAGS) -o $@ $<

clean:
	rm -f $(OBJS) $(TARGET)