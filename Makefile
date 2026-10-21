# PV-1000 Control Test
#   make          builds build/pv-1000_control_test.bin (needs z80asm)
#   make check    builds and compares the CRC32 with the released ROM
#   make dist     zips the ROM under its No-Intro name, for the release
#   make font     regenerates src/font.asm and src/font-yellow.asm (needs Python 3)
#   make clean

ROM := build/pv-1000_control_test.bin
ZIP := build/pv-1000_control_test.zip
# name of the ROM inside the zip, in the No-Intro style
NOINTRO := PV-1000 Control Test (World) (Aftermarket) (Unl).bin
# CRC32 of the current version: update it when the program changes
CRC := 32c551cf

.PHONY: all check dist font clean
all: $(ROM)

$(ROM): src/control-test.asm src/font.asm src/font-yellow.asm
	mkdir -p build
	z80asm -I src -o $@ src/control-test.asm
	sha1sum $@ | sed 's|build/||' > $@.sha1
	@echo "$@: $$(stat -c %s $@) bytes, CRC32 $$(python3 -c 'import sys,zlib;print(format(zlib.crc32(open(sys.argv[1],"rb").read()),"08x"))' $@ 2>/dev/null || echo '?')"

check: $(ROM)
	@test "$$(python3 -c 'import sys,zlib;print(format(zlib.crc32(open(sys.argv[1],"rb").read()),"08x"))' $(ROM))" = "$(CRC)" \
	  && echo "OK: CRC32 $(CRC)" || { echo "CRC32 differs from $(CRC)"; exit 1; }

# GitHub renames release assets with spaces or parentheses, so the No-Intro name goes
# inside the zip
dist: $(ZIP)
$(ZIP): $(ROM)
	rm -f $@
	python3 -c 'import sys,zipfile;zipfile.ZipFile(sys.argv[1],"w",zipfile.ZIP_DEFLATED).write(sys.argv[2],sys.argv[3])' $@ $< "$(NOINTRO)"
	@echo "$@: $(NOINTRO)"

# src/font*.asm are committed, so building needs only z80asm; regenerate them after
# changing the font
font:
	python3 tools/font.py

clean:
	rm -rf build
