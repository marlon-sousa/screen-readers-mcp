// ROLE: entity -- `bye` has no params, and answers with the shared AckResult in
// AckResult.swift. This file exists so the contract's command list and this
// directory match one for one, and so the next reader looks for `bye`'s shape
// where every other command's shape is.
//
// Pure, and empty of types by design. `bye` is the ORDERLY teardown: the
// session restores what it changed and closes the connection, which is
// behaviour (entry 13.4's Session), not shape.
//
// It therefore has NO TEST FILE, and that is a statement rather than an
// omission: there is no shape here to test, exactly as a port has no behaviour
// to test.
