// Copyright (C) 2023 Kasper Lund.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the LICENSE file.

import system.containers

DEVELOPMENT/bool ::= containers.images.any: it.name == "jaguar"
