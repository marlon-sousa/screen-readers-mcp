# This reader publishes no guidance of its own

A session is live, but the connected bridge did not announce the `guidance`
capability, so it has no written account of what your stance means on this
reader. That is a supported configuration, not a fault: a bridge with nothing
reader-specific to say leaves the capability out rather than shipping an empty
document.

**Your stance still holds in full.** It arrived with `connect_reader`'s result,
and the rule behind it is in `screenreader://guidance`:

> A command that re-reads what is already there is available to every stance. A
> command that *reaches what focus cannot* is not available to the `user` and
> `validator` stances at all.

What is missing is only the list of *which* of this particular reader's commands
fall on which side of that line. Read `screenreader://info` for the reader's name
and version, and apply what you already know about it. Where you are unsure
whether a command reaches past focus, treat it as though it does: under the
restricted stances, a task that cannot be done without it has failed, and
reaching for it anyway is the one outcome that cannot be corrected afterwards.
