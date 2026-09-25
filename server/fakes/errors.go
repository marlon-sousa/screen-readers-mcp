// screenreader-mcp fakes -- the fakes' own sentinel errors.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: supporting construct for the fakes, not a port double.
//
// A fake asked for something nobody scripted must fail rather than invent an answer.
package fakes

import "errors"

var errNothingScripted = errors.New("fake: nothing was scripted for this call")
