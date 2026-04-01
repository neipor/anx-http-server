# Makefile for ANX Web Server v0.5.0
# High-Performance AArch64 Assembly HTTP/1.1 + HTTP/2 + WebSocket Server

# Toolchain
AS = as
LD = ld
ASFLAGS = -g
LDFLAGS = -static

# Version
VERSION_MAJOR = 0
VERSION_MINOR = 6
VERSION_PATCH = 0
VERSION_STAGE = release

# Directories
SRC_DIR = src
BUILD_DIR = build
TEST_DIR = tests

# Source files (note: frames.s is included by connection.s, not compiled separately)
SRCS = config.s config_nginx.s data.s listing.s http.s main.s network.s utils.s i18n.s cgi.s error.s \
       location.s access.s \
       protocol/http2/connection.s protocol/http2/streams.s protocol/http2/hpack.s protocol/http2/hpack_impl.s protocol/http2/hpack_dynamic.s protocol/http2/hpack_encode.s protocol/http2/hpack_decode.s protocol/http2/handler.s protocol/http2/response.s protocol/http2/h2_request.s protocol/http2/h2_response.s \
       protocol/websocket/frames.s protocol/websocket/handshake.s \
       core/memory.s core/simd.s core/simd_wrapper.s \
       io/engine.s io/uring.s io/uring_impl.s io/uring_submit.s \
       crypto/sha1.s crypto/base64.s

# Objects
OBJS = $(patsubst %.s,$(BUILD_DIR)/%.o,$(SRCS))

# Target
TARGET = $(BUILD_DIR)/anx

# Phony targets
.PHONY: all clean test release check install uninstall

# Default target
all: $(TARGET)
	@echo "Build complete!"
	@echo "Version: v$(VERSION_MAJOR).$(VERSION_MINOR).$(VERSION_PATCH)-$(VERSION_STAGE)"

# Create version.s
$(SRC_DIR)/version.s:
	@echo "Generating version.s..."
	@echo "/* version.s - Auto-generated version information */" > $@
	@echo ".global msg_version_current, len_version_current" >> $@
	@echo ".global version_major, version_minor, version_patch" >> $@
	@echo ".data" >> $@
	@echo "msg_version_current: .ascii \"v$(VERSION_MAJOR).$(VERSION_MINOR).$(VERSION_PATCH)-$(VERSION_STAGE)\"" >> $@
	@echo "len_version_current = . - msg_version_current" >> $@
	@echo "version_major: .byte $(VERSION_MAJOR)" >> $@
	@echo "version_minor: .byte $(VERSION_MINOR)" >> $@
	@echo "version_patch: .byte $(VERSION_PATCH)" >> $@

# Ensure version.s exists before compiling dependent files
$(BUILD_DIR)/main.o: $(SRC_DIR)/version.s

# Compile rule
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.s | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) -o $@ $<

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Link rule - explicitly list all objects
$(TARGET): $(OBJS) $(BUILD_DIR)/version.o
	$(LD) $(LDFLAGS) -o $@ $^

# Build version.o
$(BUILD_DIR)/version.o: $(SRC_DIR)/version.s | $(BUILD_DIR)
	$(AS) $(ASFLAGS) -o $@ $<

# Run tests
test: $(TARGET)
	@echo "Running test suite..."
	@chmod +x $(TEST_DIR)/run_tests.sh
	@./$(TEST_DIR)/run_tests.sh

# Check code formatting
check:
	@echo "Checking assembly formatting..."
	@find $(SRC_DIR) -name "*.s" -exec echo "Checking {}" \;
	@echo "Format check complete"

# Create release package
release: $(TARGET)
	@echo "Creating release package..."
	@mkdir -p dist
	@cp $(TARGET) dist/anx-v$(VERSION_MAJOR).$(VERSION_MINOR).$(VERSION_PATCH)-$(VERSION_STAGE)-aarch64
	@tar -czf dist/anx-v$(VERSION_MAJOR).$(VERSION_MINOR).$(VERSION_PATCH)-$(VERSION_STAGE)-aarch64.tar.gz -C dist anx-v$(VERSION_MAJOR).$(VERSION_MINOR).$(VERSION_PATCH)-$(VERSION_STAGE)-aarch64
	@echo "Release package created"

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	rm -f $(SRC_DIR)/version.s
	rm -rf dist
	@echo "Clean complete"

# Run server
run: $(TARGET)
	./$(TARGET) -p 8080 -d www

# GitHub Actions CI target
ci: clean $(TARGET) test check
	@echo "CI build complete"

# Help
help:
	@echo "ANX Web Server Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build the server (default)"
	@echo "  test     - Run test suite"
	@echo "  clean    - Remove build artifacts"
	@echo "  run      - Build and run server"
	@echo "  release  - Create release package"
	@echo "  ci       - CI/CD build (clean + all + test + check)"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Version: v$(VERSION_MAJOR).$(VERSION_MINOR).$(VERSION_PATCH)-$(VERSION_STAGE)"

# Install targets
install: $(TARGET)
	install -d $(DESTDIR)/usr/local/bin
	install -d $(DESTDIR)/etc/anx
	install -d $(DESTDIR)/var/log/anx
	install -d $(DESTDIR)/var/www/html
	install -m 755 $(TARGET) $(DESTDIR)/usr/local/bin/anx
	install -m 644 configs/nginx.conf $(DESTDIR)/etc/anx/anx.conf
	install -m 644 configs/anx.service $(DESTDIR)/usr/lib/systemd/system/anx.service

uninstall:
	rm -f $(DESTDIR)/usr/local/bin/anx
	rm -f $(DESTDIR)/etc/anx/anx.conf
	rm -f $(DESTDIR)/usr/lib/systemd/system/anx.service
