// Copyright (C) 2023 Kasper Lund.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the LICENSE file.

import esp32
import system.firmware
import system.storage
import system.containers

DEVELOPMENT/bool ::= containers.images.any: it.name == "jaguar"
RUNNING/bool ::= (ZYGOTE_STORE_.get ZYGOTE_STATE_KEY_) != ZYGOTE_STATE_SETUP_

run_application -> none:
  ZYGOTE_STORE_.remove ZYGOTE_STATE_KEY_
  esp32.deep_sleep (Duration --ms=10)

run_setup -> none:
  // Never persist the "setup" state from an unvalidated OTA image:
  // `esp32.deep_sleep` before `firmware.validate` causes the ESP-IDF
  // bootloader to abort the new image and roll back to the previous
  // slot, which would otherwise wake up stuck in setup mode.
  if not firmware.is_validation_pending:
    ZYGOTE_STORE_[ZYGOTE_STATE_KEY_] = ZYGOTE_STATE_SETUP_
  esp32.deep_sleep (Duration --ms=10)

has_wifi_configuration -> bool:
  if has_firmware_wifi_configuration_: return true
  // An image booting with `is_validation_pending` was just installed
  // over the network via OTA; always let the application try `net.open`
  // with the SDK's saved NVS credentials even if the previous firmware
  // predated the zygote `wifi-configured` flag.
  if firmware.is_validation_pending: return true
  return ZYGOTE_STORE_.get ZYGOTE_WIFI_CONFIGURED_KEY_ --if-absent=(: false)

mark_wifi_configured -> none:
  ZYGOTE_STORE_[ZYGOTE_WIFI_CONFIGURED_KEY_] = true

clear_wifi_configured -> none:
  if not firmware.is_validation_pending:
    ZYGOTE_STORE_.remove ZYGOTE_WIFI_CONFIGURED_KEY_

is_missing_wifi_configuration_error exception/any -> bool:
  return "$exception".contains "wifi ssid not provided"

has_firmware_wifi_configuration_ -> bool:
  ssid := firmware.config[WIFI_SSID_KEY_]
  return ssid is string and ssid != ""

ZYGOTE_STORE_       ::= storage.Bucket.open --flash "github.com/kasperl/toit-zygote"
ZYGOTE_STATE_KEY_   ::= "state"
ZYGOTE_STATE_SETUP_ ::= "setup"
ZYGOTE_WIFI_CONFIGURED_KEY_ ::= "wifi-configured"
WIFI_SSID_KEY_      ::= "wifi.ssid"
