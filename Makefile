AS = as
LD = ld
ASFLAGS = -g
LDFLAGS = -static

BUILD_DIR = build
TARGET = $(BUILD_DIR)/anx_asm_demo

# Find all assembly source files
SRCS = $(wildcard src/*.s)
# Exclude defs.s because it is included via .include, not linked
LINK_SRCS = $(filter-out src/defs.s, $(SRCS))
OBJS = $(LINK_SRCS:src/%.s=$(BUILD_DIR)/%.o)

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
