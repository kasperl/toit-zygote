# Copyright (C) 2023 Kasper Lund.
# Use of this source code is governed by a Zero-Clause BSD license that can
# be found in the LICENSE file.

CHIP          ?= esp32
TOIT          ?= toit
SDK_VERSION   ?= $(shell $(TOIT) version)
# The default 1a0000 OTA slot (~1.62 MiB) is ~6 KiB too small to hold
# both the app and setup containers on recent Toit SDKs; use the
# 1c0000 (~1.75 MiB) variant published by toitlang/envelopes.
ENVELOPE_NAME ?= firmware-$(CHIP)-ota-1c0000
ENVELOPE_URL  ?= https://github.com/toitlang/envelopes/releases/download/$(SDK_VERSION)/$(ENVELOPE_NAME).envelope.gz
BASE_ENVELOPE  = build/firmware-base-$(SDK_VERSION)-$(ENVELOPE_NAME).envelope

.PHONY: all
all: test

.PHONY: firmware
firmware: build/firmware.envelope

.PHONY: clean
clean:
	rm -rf build

#############################################################################
# Tests
#############################################################################

.PHONY: build/CMakeCache.txt
build/CMakeCache.txt:
	$(MAKE) rebuild-cmake

.PHONY: install-pkgs
install-pkgs: rebuild-cmake
	cmake --build build --target install-pkgs

.PHONY: test
test: install-pkgs rebuild-cmake
	cmake --build build --target check

.PHONY: rebuild-cmake
rebuild-cmake:
	mkdir -p build
	cmake -B build -DCMAKE_BUILD_TYPE=Debug

#############################################################################
# Firmware demo
#############################################################################

$(BASE_ENVELOPE):
	mkdir -p $(dir $@)
	curl -fsSL $(ENVELOPE_URL) | gunzip > $@.tmp
	mv $@.tmp $@

build/firmware.envelope: build/app.snapshot build/setup.snapshot $(BASE_ENVELOPE)
	mkdir -p $(dir $@)
	cp $(BASE_ENVELOPE) $@
	$(TOIT) tool firmware -e $@ container install app build/app.snapshot
	$(TOIT) tool firmware -e $@ container install setup build/setup.snapshot

build/app.snapshot: src/main.toit src/mode.toit package.lock
	mkdir -p $(dir $@)
	$(TOIT) compile -O2 --snapshot -o $@ $<

build/setup.snapshot: src/setup.toit src/mode.toit package.lock
	mkdir -p $(dir $@)
	$(TOIT) compile -O2 --snapshot -o $@ $<
