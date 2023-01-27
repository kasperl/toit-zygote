# Copyright (C) 2023 Kasper Lund.
# Use of this source code is governed by a Zero-Clause BSD license that can
# be found in the LICENSE file.

CHIP   = esp32
JAGUAR = $(HOME)/.cache/jaguar

.PHONY: firmware
firmware: build/firmware.envelope

.PHONY: clean
clean:
	rm -rf build

#############################################################################

build/firmware.envelope: build/app.snapshot
build/firmware.envelope: build/setup.snapshot
build/firmware.envelope: $(JAGUAR)/assets/firmware-$(CHIP).envelope
	mkdir -p $(dir $@)
	cp $< $@
	$(JAGUAR)/sdk/tools/firmware -e $@ container install app build/app.snapshot
	$(JAGUAR)/sdk/tools/firmware -e $@ container install setup build/setup.snapshot

.PHONY: build/app.snapshot
build/app.snapshot: src/main.toit
	mkdir -p $(dir $@)
	$(JAGUAR)/sdk/bin/toit.compile -w $@ $<

.PHONY: build/setup.snapshot
build/setup.snapshot: src/setup.toit
	mkdir -p $(dir $@)
	$(JAGUAR)/sdk/bin/toit.compile -w $@ $<
