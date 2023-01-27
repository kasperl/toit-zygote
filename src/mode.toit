// Copyright (C) 2023 Kasper Lund.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the LICENSE file.

import device
import esp32
import system.containers

DEVELOPMENT/bool ::= containers.images.any: it.name == "jaguar"
RUNNING/bool ::= (ZYGOTE_STORE_.get ZYGOTE_STATE_KEY_) != ZYGOTE_STATE_SETUP_

run_application -> none:
  ZYGOTE_STORE_.delete ZYGOTE_STATE_KEY_
  esp32.deep_sleep (Duration --ms=10)

run_setup -> none:
  ZYGOTE_STORE_.set ZYGOTE_STATE_KEY_ ZYGOTE_STATE_SETUP_
  esp32.deep_sleep (Duration --ms=10)

ZYGOTE_STORE_       ::= device.FlashStore
ZYGOTE_STATE_KEY_   ::= "zygote.state"
ZYGOTE_STATE_SETUP_ ::= "zygote.setup"
