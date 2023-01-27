// Copyright (C) 2023 Kasper Lund.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the LICENSE file.

import net.wifi

import .mode as mode

main:
  // We allow the setup container to start and eagerly terminate
  // if we don't need it yet. This makes it possible to have
  // the setup container installed always, but have it run with
  // the -D jag.disabled flag in development.
  if mode.RUNNING: return

  // TODO(kasper): Convert this printing into something useful.
  channels := (ByteArray 12: it + 1)
  found := wifi.scan channels
  print (found.map: it.ssid)

  // TODO(kasper): Transition to running the application only
  // after getting a new WiFi.
  mode.run_application
