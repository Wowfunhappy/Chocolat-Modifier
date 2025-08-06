# Chocolat Modifier Makefile

# Compiler and flags
CC = clang
CFLAGS = -dynamiclib -framework Foundation -framework AppKit -undefined dynamic_lookup -fobjc-arc
OUTPUT = ChocolatModifier.dylib
# Find all .m files in current directory and ZKSwizzle subdirectory
SOURCES = $(wildcard *.m) $(wildcard ZKSwizzle/*.m)
INSTALL_PATH = /Applications/Chocolat.app/Contents/Frameworks

# Default target
all: $(OUTPUT)

# Build the dylib
$(OUTPUT): $(SOURCES)
	$(CC) $(CFLAGS) -o $@ $^

# Clean build artifacts
clean:
	rm -f $(OUTPUT)

# Install dylib to Chocolat.app
install: $(OUTPUT)
	@echo "Installing ChocolatModifier.dylib to $(INSTALL_PATH)..."
	@cp -f $(OUTPUT) "$(INSTALL_PATH)/"
	@echo "Installation complete."

.PHONY: all clean install