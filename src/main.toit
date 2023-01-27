// Copyright (C) 2023 Kasper Lund.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the LICENSE file.

import log
import net

import .mode as mode

main:
  // If the setup container is supposed to run, we allow
  // the application container to terminate eagerly. This
  // allows the two containers to always start without
  // interfering with each other.
  if not mode.RUNNING: return

  if mode.DEVELOPMENT: log.info "running in development"

  while true:
    network/net.Interface? := null
    try:
      network = net.open
      // TODO(kasper): Check that the network has a connection.
      run network
    finally:
      if network: network.close

run network/net.Interface:
  // TODO(kasper): Do something with the network.
  sleep (Duration --s=5)
  if (random 100) < 5: mode.run_setup
