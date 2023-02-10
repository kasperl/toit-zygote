// Copyright (C) 2023 Kasper Lund.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the LICENSE file.

import esp32
import system.storage
import system.containers

DEVELOPMENT/bool ::= containers.images.any: it.name == "jaguar"
RUNNING/bool ::= (ZYGOTE_STORE_.get ZYGOTE_STATE_KEY_) != ZYGOTE_STATE_SETUP_

run_application -> none:
  ZYGOTE_STORE_.remove ZYGOTE_STATE_KEY_
  esp32.deep_sleep (Duration --ms=10)

run_setup -> none:
  ZYGOTE_STORE_[ZYGOTE_STATE_KEY_] = ZYGOTE_STATE_SETUP_
  esp32.deep_sleep (Duration --ms=10)

ZYGOTE_STORE_       ::= storage.Bucket.open --flash "github.com/kasperl/toit-zygote"
ZYGOTE_STATE_KEY_   ::= "state"
ZYGOTE_STATE_SETUP_ ::= "setup"
