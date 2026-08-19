# The tools this server offers

Every tool this server has, listed whether or not a reader is connected and
whether or not the reader in front of you could run it. For each one: what it is
for, the capability that gates it, the parameters it takes, and the shape of a
successful result -- both as JSON Schema, so you can copy them rather than
paraphrase them.

Read it before you connect. Nothing in it changes during a session.

## What it does not answer

This document says what this server **offers** and what each tool **needs**. It
does not say what you can call at this instant, and that is deliberate: a
document filtered to the current session would show an agent that has not
connected yet exactly the handful it can already see, which is the gap this
document exists to close.

The other half of the question is a live fact, and it is published separately.
`screenreader://info` reports the capabilities the connected reader announced,
from the same vocabulary this document groups tools by. Intersect the two and you
know what is callable right now. Neither answer can go stale, because neither
depends on the other's timing.

## How the gate works

A tool is gated on at most one capability. A reader announces its capabilities
when the session opens, and the tools those capabilities allow are advertised
from that moment until the session ends. The ungated ones are there the whole
time -- they are how you find a reader, open a session, end it, and ask whether
it is still alive.

A capability a reader never announced is not a fault in this server and not
something to retry: it is a reader that does not do that thing. Another reader
may.

## What a failure looks like

A tool that fails comes back as a **result with `isError` set** and a
human-readable message in its content -- never as a protocol-level error. You can
read that message and correct yourself within the same turn.

Two failures are worth telling apart, and the message distinguishes them:

- **Nothing is connected at all.** Open a session, then call again.
- **A reader is connected and never announced the capability this tool needs.**
  The message names the reader and the capability. Reconnecting will not change
  the answer; that reader does not do it.

## About the schemas

Each tool carries two: the parameters it accepts, and the shape of a
**successful** result. The result schema describes success only -- a failure
carries the prose above, not a structure.

They are written by hand, beside the code that produces them, and checked against
it: a property named here is one the result really marshals, and a property
listed as required is one that is always present. Where a field can be absent,
the schema says so and its description says what the absence *means* -- which is
usually a real answer rather than a gap.

For **how** to drive a reader -- the loop, what an empty result does and does not
tell you, and who you are standing in for -- read `screenreader://guidance`. That
document is the method; this one is the reference.
