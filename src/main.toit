// Copyright (C) 2023 Kasper Lund.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the LICENSE file.

import log
import .mode as mode

main:
  if mode.DEVELOPMENT: log.info "running in development"
