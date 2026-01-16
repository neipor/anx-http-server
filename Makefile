# Makefile for AArch64 Assembly HTTP Server

AS = as
LD = ld
ASFLAGS = -g
LDFLAGS = -static

# Directories
SRC_DIR = src
BUILD_DIR = build

# Sources
SRCS = $(SRC_DIR)/config.s \
       $(SRC_DIR)/data.s \
       $(SRC_DIR)/listing.s \
       $(SRC_DIR)/http.s \
       $(SRC_DIR)/main.s \
       $(SRC_DIR)/network.s \
       $(SRC_DIR)/utils.s \
       $(SRC_DIR)/i18n.s \
       $(SRC_DIR)/cgi.s \
       $(SRC_DIR)/version.s

# Objects
OBJS = $(patsubst $(SRC_DIR)/%.s,$(BUILD_DIR)/%.o,$(SRCS))

# Target
TARGET = $(BUILD_DIR)/anx

.PHONY: all clean run

all: $(TARGET)

# Generate version.s dynamically
$(SRC_DIR)/version.s:
	@echo "Generating version info: $$(git describe --always --dirty)"
	@echo ".global msg_version_current, len_version_current" > $@
	@echo ".data" >> $@
	@echo "msg_version_current: .ascii \"$$(git describe --always --dirty)\"" >> $@
	@echo "len_version_current = . - msg_version_current" >> $@

# Compile rule
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.s
	@mkdir -p $(BUILD_DIR)
	$(AS) $(ASFLAGS) -o $@ $<

# Link rule
$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $(OBJS)

clean:
	rm -rf $(BUILD_DIR) $(SRC_DIR)/version.s

run: all
	./$(TARGET)
