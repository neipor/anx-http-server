AS = as
LD = ld
ASFLAGS = -g
LDFLAGS = -static

BUILD_DIR = build
TARGET = $(BUILD_DIR)/anx_asm_demo

SRCS = src/server.s
OBJS = $(SRCS:src/%.s=$(BUILD_DIR)/%.o)

.PHONY: all clean

all: $(BUILD_DIR) $(TARGET)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $^

$(BUILD_DIR)/%.o: src/%.s | $(BUILD_DIR)
	$(AS) $(ASFLAGS) -o $@ $<

clean:
	rm -rf $(BUILD_DIR)