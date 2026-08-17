# No reader is connected

This resource carries the **connected reader's own** account of the stance you
declared -- what the ordinary vocabulary is on that reader, and which of its
commands fall outside it. It cannot exist before a session does: the reader is
what fixes the platform, and until `connect_reader` succeeds there is no reader
to ask.

That is not the awkward ordering it looks like. The persona is chosen *before*
connecting, because it decides what the run will mean; its instantiation on a
particular reader can only be fetched *after*. `connect_reader`'s result names
this resource at the first instant it exists.

**Read `screenreader://guidance` now.** It is static, it is readable before any
session, and it holds what you need in order to choose: what a screen reader is,
how this server is meant to be driven, and a profile of each stance you may
declare. Then connect, and come back here.
