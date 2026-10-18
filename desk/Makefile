# make nes          build/desk.nes
# make rbf          build/desk.rbf, the mapper 773 core, on the EverDrive N8 Pro base fetched into ../rtl/base
# make run          Desk and its core onto the cart through edn8.py and started, from the menu or a running Desk
# make shot         Desk in tools/nesemu.py on an empty card, its frames saved (SHOT_ARGS, SHOT_SD)
# make kbdtest      build/kbdtest.nes, the port 2 USB adapter, port 1 PS/2 and the Family BASIC keyboard, on the cart
# make kbdshot      kbdtest in tools/nesemu.py (KBD_ARGS)
# make linktest     build/linktest.nes, packets echoed through the port 2 adapter's link, on the cart
# make linkshot     linktest in tools/nesemu.py against its adapter model (LINK_ARGS)
# make speedtest    build/speedtest.nes, port 2 transfer rates down and up, on the cart
# make speedshot    speedtest in tools/nesemu.py against its adapter model (SPEED_ARGS)

QUARTUS ?= $(HOME)/altera_lite/25.1std/quartus/bin
ROOT    ?= ..
VENV    ?= $(ROOT)/.venv
PY      ?= $(VENV)/bin/python
EDN8    ?= $(ROOT)/edn8.py
EDN8_PRO ?= https://github.com/krikzz/EDN8-PRO
EDN8_REV ?= 317f8caf8d2b917a260e94ec14d5edbbbfced8ba

RBF = build/desk.rbf
NES = build/desk.nes
BASE = $(ROOT)/rtl/base
BASE_OK = $(BASE)/.fetched
VENV_OK = $(VENV)/.installed
RTL = $(wildcard rtl/*.sv) $(ROOT)/rtl/menu_ret.sv $(BASE_OK)
# the keyboard drivers and font, shared with the test ROMs
KBD_INC = $(ROOT)/nes/include
FONT = $(ROOT)/nes/data/background.chr
NES_SRC = $(wildcard nes/src/*.s)
NES_INC = $(wildcard nes/include/*.inc) $(KBD_INC)/keyboard/adapter.inc
KBD_ADAPTER = $(ROOT)/nes/src/keyboard/adapter.s
KBD_PS2 = $(ROOT)/nes/src/keyboard/ps2.s
NES_OBJ = $(NES_SRC:nes/src/%.s=build/nes/%.o) build/nes/adapter.o

QFLOW = cd quartus && \
	$(QUARTUS)/quartus_map top --write_settings_files=off && \
	$(QUARTUS)/quartus_fit top --write_settings_files=off && \
	$(QUARTUS)/quartus_asm top --write_settings_files=off && \
	$(QUARTUS)/quartus_sta top

.PHONY: rbf nes run shot kbdtest kbdshot linktest linkshot speedtest speedshot

rbf: $(RBF)
nes: $(NES)

$(VENV_OK): $(ROOT)/requirements.txt
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install -q -r $<
	touch $@

# krikzz's base at a pinned commit, with the menu-return hooks Desk's mapper needs
$(BASE_OK): $(ROOT)/rtl/base.patch
	rm -rf build/EDN8-PRO $(BASE)
	git clone -q --filter=blob:none $(EDN8_PRO) build/EDN8-PRO
	git -C build/EDN8-PRO checkout -q $(EDN8_REV)
	mkdir -p $(BASE)
	cp build/EDN8-PRO/fpga/base_sv/*.sv build/EDN8-PRO/fpga/base_sv/*.sdc $(BASE)/
	patch -p1 -F0 -d $(BASE) < $<
	touch $@

$(RBF): $(RTL) quartus/top.qsf
	@mkdir -p build
	$(QFLOW) && cp output_files/top.rbf ../$@

UI_BIN = build/font.bin build/tool.bin build/desk.bin build/caption.bin build/caption_off.bin build/sb.bin
SYS_PALS = build/exe_16.pal build/folder_16.pal build/rom_16.pal
GFX_TOOLS = tools/nesgfx.py tools/deskinc.py tools/mkapptiles.py tools/mkicons.py

build/desk.chr $(UI_BIN) $(SYS_PALS) &: tools/mkchr.py $(GFX_TOOLS) \
		$(FONT) assets/cursors.png $(wildcard icons/*.png) nes/include/desk.inc | $(VENV_OK)
	@mkdir -p build
	$(PY) tools/mkchr.py --font $(FONT) --cursors assets/cursors.png \
		--icons icons --inc nes/include/desk.inc --pals build --out-dir build -o build/desk.chr

build/nes/tiles.o: build/desk.chr
build/nes/gfx.o: $(UI_BIN)
build/nes/icons.o: $(SYS_PALS)

build/nes/%.o: nes/src/%.s $(NES_INC)
	@mkdir -p $(dir $@)
	ca65 -g -I nes/include -I $(KBD_INC) --bin-include-dir build -o $@ $<

# the port 2 USB keyboard and mouse driver
build/nes/adapter.o: $(KBD_ADAPTER) $(KBD_INC)/keyboard/adapter.inc
	@mkdir -p $(dir $@)
	ca65 -g -I $(KBD_INC) -o $@ $<

build/desk.prg: $(NES_OBJ) nes/conf/ld.cfg tools/bankcheck.py | $(VENV_OK)
	ld65 -C nes/conf/ld.cfg -m build/desk.map -Ln build/desk.lbl --dbgfile build/desk.dbg -o $@ $(NES_OBJ)
	$(PY) tools/bankcheck.py --map build/desk.map $(NES_SRC) $(KBD_ADAPTER) || { rm -f $@; exit 1; }

$(NES): build/desk.prg tools/mknes.py
	$(PY) tools/mknes.py build/desk.prg -o $@

# Desk is the menu edn8.py talks to once it runs, so a second run replaces it in place
run: $(NES) $(RBF) | $(VENV_OK)
	$(PY) tools/desk.py menu
	$(PY) $(EDN8) run $(NES) --rbf $(RBF)
	$(PY) tools/desk.py status

# Desk in tools/nesemu.py on a card of its own, build/sd; SHOT_SD adds a host folder's files to it, SHOT_ARGS
# presses buttons and saves frames
SHOT_ARGS ?= --frames 120 --shot 119:build/shot.png
SHOT_SD ?=
shot: build/desk.prg | $(VENV_OK)
	rm -rf build/sd
	mkdir -p build/sd/nespc/apps build/sd/nespc/menu build/sd/nespc/desktop build/sd/nespc/system
	$(if $(SHOT_SD),cp -r $(SHOT_SD)/. build/sd/)
	$(PY) tools/nesemu.py build/desk.prg --sd build/sd $(SHOT_ARGS)

# the test ROMs: each on testlib's reset, menu return and text and Desk's adapter.o, linktest on kbdtest's ld.cfg
TESTS = kbdtest linktest speedtest
TEST_DIR = $(ROOT)/tests
TESTLIB = build/testlib.o
$(TESTLIB): $(TEST_DIR)/testlib/testlib.s $(TEST_DIR)/testlib/testlib.inc nes/include/desk.inc $(FONT)
	@mkdir -p build
	ca65 -I nes/include -I $(TEST_DIR)/testlib --bin-include-dir $(dir $(FONT)) -o $@ $<

.SECONDEXPANSION:
$(TESTS:%=build/%.nes): build/%.nes: $(TEST_DIR)/$$*/$$*.s \
		$$(firstword $$(wildcard $(TEST_DIR)/$$*/ld.cfg) $(TEST_DIR)/kbdtest/ld.cfg) \
		nes/include/desk.inc tools/mknes.py $(TEST_DIR)/testlib/testlib.inc $(TESTLIB) build/nes/adapter.o | $(VENV_OK)
	@mkdir -p build/$*
	ca65 -I nes/include -I $(KBD_INC) -I $(TEST_DIR)/testlib -o build/$*/$*.o $<
	ld65 -C $(word 2,$^) -m build/$*/$*.map -o build/$*/$*.prg build/$*/$*.o build/nes/adapter.o \
		$(filter %/ps2.o,$^) $(TESTLIB)
	$(PY) tools/mknes.py build/$*/$*.prg -o $@

build/kbdtest.nes: build/kbdtest/ps2.o
build/kbdtest/ps2.o: $(KBD_PS2) $(KBD_INC)/keyboard/ps2.inc
	@mkdir -p $(dir $@)
	ca65 -I $(KBD_INC) -o $@ $<

$(TESTS): %: build/%.nes $(RBF) | $(VENV_OK)
	$(PY) tools/desk.py menu
	$(PY) $(EDN8) run $< --rbf $(RBF)

# --key 10:Q:10 holds keys, --stuck out1=0 a line, --type '10:ls\r' types on the adapter, --pad2 0x4B, --ps2 '10:ls\r'
KBD_ARGS ?= --frames 40 --key 10:Q:10 --shot 39:build/kbdshot.png
LINK_ARGS ?= --frames 120 --adapter --shot 119:build/linkshot.png
SPEED_ARGS ?= --frames 260 --adapter --shot 259:build/speedshot.png
kbdshot: TEST_ARGS = $(KBD_ARGS)
linkshot: TEST_ARGS = $(LINK_ARGS)
speedshot: TEST_ARGS = $(SPEED_ARGS)
kbdshot linkshot speedshot: %shot: build/%test.nes
	$(PY) tools/nesemu.py build/$*test/$*test.prg $(TEST_ARGS)
