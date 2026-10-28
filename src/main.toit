// Copyright (C) 2023 Kasper Lund.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the LICENSE file.

import esp32
import log
import net
import ntp

import .mode as mode

RETRIES ::= mode.DEVELOPMENT ? 2 : 5
PERIOD  ::= mode.DEVELOPMENT ? (Duration --s=10) : (Duration --m=1)

main:
  // If the setup container is supposed to run, we allow
  // the application container to terminate eagerly. This
  // allows the two containers to always start without
  // interfering with each other.
  if not mode.RUNNING: return

  // If the device has never been configured (no firmware-baked
  // WiFi credentials and no flag in our zygote bucket), hand
  // control to the setup container immediately. We rely on the
  // recorded `wifi-configured` flag rather than waiting for
  // `net.open` to throw, because the SDK's WiFi service can
  // hang indefinitely when no credentials are available instead
  // of returning the "wifi ssid not provided" error to the
  // caller.
  if not mode.has-wifi-configuration:
    log.info "wifi has never been configured; entering setup mode"
    mode.run-setup
    return

  retries := 0
  while ++retries < RETRIES:
    network/net.Interface? := null
    exception := catch --trace:
      network = net.open
      mode.mark-wifi-configured
      run network
      retries = 0
    if network: network.close
    if exception and mode.is-missing-wifi-configuration-error exception:
      log.info "wifi is not configured; entering setup mode"
      mode.clear-wifi-configured
      mode.run-setup
    sleep PERIOD

  // We keep failing to connect or run the app. We assume
  // that this is because we've got the wrong WiFi credentials
  // so we enter the setup mode.
  mode.run-setup

run network/net.Interface:
  tags/Map? := null
  if mode.DEVELOPMENT: tags = {"mode": "development"}

  while true:
    log.info "running" --tags=tags
    result := ntp.synchronize --network=network
    if result:
      log.info "contacted ntp server" --tags={
        "adjustment" : result.adjustment,
        "accuracy"   : result.accuracy,
      }
    sleep PERIOD
