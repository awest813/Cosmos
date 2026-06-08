#
# Cross-compile the steamwebhelper wrapper from macOS for Windows x86_64.
# Upstream: notpop/steam-on-m1-wine (MIT)
#
# make        build ./steamwebhelper.exe
# make clean  remove build artefacts
#
# Requires Homebrew mingw-w64: brew install mingw-w64

TARGET ?= steamwebhelper.exe
CC ?= x86_64-w64-mingw32-gcc
CFLAGS ?= -O2 -Wall -Wextra -Wpedantic -municode -DUNICODE -D_UNICODE
LDFLAGS ?= -static -lshell32 -mwindows
SRC = src/steamwebhelper-wrapper.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(TARGET)
