// Copyright (C) 2023 Kasper Lund.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the LICENSE file.

import esp32
import system.firmware
import system.storage
import system.containers

DEVELOPMENT/bool ::= containers.images.any: it.name == "jaguar"
RUNNING/bool ::= (ZYGOTE-STORE_.get ZYGOTE-STATE-KEY_) != ZYGOTE-STATE-SETUP_

run-application -> none:
  ZYGOTE-STORE_.remove ZYGOTE-STATE-KEY_
  esp32.deep-sleep (Duration --ms=10)

run-setup -> none:
  // Never persist the "setup" state from an unvalidated OTA image:
  // `esp32.deep-sleep` before `firmware.validate` causes the ESP-IDF
  // bootloader to abort the new image and roll back to the previous
  // slot, which would otherwise wake up stuck in setup mode.
  if not firmware.is-validation-pending:
    ZYGOTE-STORE_[ZYGOTE-STATE-KEY_] = ZYGOTE-STATE-SETUP_
  esp32.deep-sleep (Duration --ms=10)

has-wifi-configuration -> bool:
  if has-firmware-wifi-configuration_: return true
  // An image booting with `is-validation-pending` was just installed
  // over the network via OTA; always let the application try `net.open`
  // with the SDK's saved NVS credentials even if the previous firmware
  // predated the zygote `wifi-configured` flag.
  if firmware.is-validation-pending: return true
  return ZYGOTE-STORE_.get ZYGOTE-WIFI-CONFIGURED-KEY_ --if-absent=(: false)

mark-wifi-configured -> none:
  ZYGOTE-STORE_[ZYGOTE-WIFI-CONFIGURED-KEY_] = true

clear-wifi-configured -> none:
  if not firmware.is-validation-pending:
    ZYGOTE-STORE_.remove ZYGOTE-WIFI-CONFIGURED-KEY_

is-missing-wifi-configuration-error exception/any -> bool:
  return "$exception".contains "wifi ssid not provided"

has-firmware-wifi-configuration_ -> bool:
  ssid := firmware.config[WIFI-SSID-KEY_]
  return ssid is string and ssid != ""

ZYGOTE-STORE_               ::= storage.Bucket.open --flash "github.com/kasperl/toit-zygote"
ZYGOTE-STATE-KEY_           ::= "state"
ZYGOTE-STATE-SETUP_         ::= "setup"
ZYGOTE-WIFI-CONFIGURED-KEY_ ::= "wifi-configured"
WIFI-SSID-KEY_              ::= "wifi.ssid"
