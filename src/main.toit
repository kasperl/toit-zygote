// Copyright (C) 2023 Kasper Lund.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the LICENSE file.

import artemis
import esp32
import log
import net
import ntp

import .mode as mode
import .setup as setup

RETRIES ::= mode.DEVELOPMENT ? 2 : 5
PERIOD  ::= mode.DEVELOPMENT ? (Duration --s=10) : (Duration --m=1)

main:
  if not artemis.available:
    // If the setup container is supposed to run, we allow
    // the application container to terminate eagerly. This
    // allows the two containers to always start without
    // interfering with each other.
    if not mode.RUNNING: return

  retries := 0
  while ++retries < RETRIES:
    log.info "trying to run app ($retries)"
    network/net.Interface? := null
    exception := catch --trace:
      network = net.open
      run network
      retries = 0
    if network: network.close
    sleep PERIOD

  // We keep failing to connect or run the app. We assume
  // that this is because we've got the wrong WiFi credentials
  // so we enter the setup mode.
  if artemis.available:
    artemis.run --offline --timeout=setup.TIMEOUT + (Duration --s=10):
      catch --unwind=(: it != DEADLINE_EXCEEDED_ERROR):
        setup.run
    artemis.Container.current.restart
  else:
    mode.run_setup

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
