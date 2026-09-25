#!/usr/bin/env python3
# Live test driver: stand in for an MCP client and drive the real
# screenreader-mcp binary over stdio against a real, running NVDA bridge.
#
# Everything is real here, so it needs a human who can hear the speech; see CONTRIBUTING.md,
# "Setting up to test against a live NVDA".
#
# Usage:
#   py -3.13 scripts/live_test.py <binary> <scenario> [--live|--silent] [--auto]
#
# Run it with no arguments for the list of scenarios.

from __future__ import annotations

import json
import os
import queue
import re
import subprocess
import sys
import threading
import time

DEFAULT_ANNOUNCE = "This is the agent, speaking through NVDA. If you can hear this, announce works."

USAGE = """\
Live test driver -- drive the real screenreader-mcp binary against a running NVDA.

  py -3.13 scripts/live_test.py <binary> <scenario> [--live|--silent] [--auto]

Scenarios (each is one checklist item group; run them in a terminal for the
guided, interactive experience):
  smoke       connect, prove tool gating, read screenreader://info, ANNOUNCE
              (you should hear it). No window focus needed.
  persona     spec 0029: connect as each of user/validator/expert; the
              declaration reaches status, screenreader://info and the bridge's
              own transcript on disk, and you HEAR two ascending tones then
              "MCP session open, as <persona>". No window focus needed.
  guidance    spec 0029 part 4: screenreader://reader-guidance hands over the
              INSTALLED add-on's own document for each stance -- the ordinary
              vocabulary on NVDA and the gestures that fall outside it, framed
              with the precedence rule. Proves the .md files were packaged,
              which nothing headless can. No window focus needed.
  capture     a gesture's speech is captured cleanly, ranges join, an absent
              wait times out. Needs a browse-mode document focused.
  braille     read the braille display; its indices are their own space.
  finddialog  drive EnhancedFindDialog end to end. Needs a browse-mode document.
  lifecycle   disconnect retracts the tools and a gated call errors; reconnect
              works; status is proven on the wire. No focus needed.
  log         spec 0021 items 1-7: a command's span holds what it CAUSED,
              positions mark and re-read without consuming, a poll loop neither
              repeats nor skips, lastSeconds needs no prior mark, wait_for_log
              wakes at the moment. Connects at debug. No focus needed.
  logerror    spec 0021 item 6's other half: the agent CAUSES a real NVDA error
              and its own wait wakes on it. Opens the Python console, checking
              it took focus first; nothing is typed if focus is wrong.
  logwatch    the same item, asked for instead of caused: a 60 s window in which
              YOU provoke an error while the agent waits. Works whatever your
              keymap is, and is the truer form of "watch what I do".
  logsilent   spec 0021 items 8-9: exactly one suppression marker pair in NVDA's
              own log, and a suppressed utterance still carries a journal
              coordinate. Always silent, whatever the flag says.
  silence     board entry 11.25: the silence cap counts only what the human
              HEARS. Narration carried on pressGesture/typeText/setLogLevel
              restarts its clock; nothing else does. Always silent; ~6 minutes.
  run         ADVANCED: one command per line from stdin. For ad-hoc probing.

--auto skips setup pauses and marks audible checks EAR (the default off a
non-terminal). See CONTRIBUTING.md, "Setting up to test against a live NVDA"."""


def main(argv: list[str]) -> int:
	args = list(argv[1:])
	if len(args) < 2:
		print(USAGE)
		return 2
	binary, scenario = args[0], args[1]
	flags = args[2:]

	mode = "silent" if "--silent" in flags else "live"
	auto = "--auto" in flags or (not sys.stdin.isatty() and "--interactive" not in flags)
	console = Console(auto)

	server = Server(binary)
	checks = Checklist()
	try:
		server.initialize()
		fn = SCENARIOS.get(scenario)
		if fn is None:
			if scenario == "run":
				return scenario_run(server, mode)
			print(f"unknown scenario {scenario!r}\n\n{USAGE}")
			return 2
		fn(server, console, checks, mode)
		return checks.summary()
	except Exception as exc:
		print(f"\n!! ABORTED: {exc}", file=sys.stderr)
		err = server.stderr_tail()
		if err:
			print("---- server stderr ----\n" + err, file=sys.stderr)
		return 1
	finally:
		server.close()


def scenario_smoke(server, console, checks, mode):
	before = server.tool_names()
	console.note(f"tools before connect: {', '.join(before)}")
	checks.check(
		"gating: only the ungated four before connect",
		set(before) == {"list_readers", "connect_reader", "disconnect_reader", "status"},
		detail=str(before),
	)

	readers = server.tool("list_readers")
	names = [r.get("reader") for r in readers.get("readers", [])]
	console.note(f"list_readers: {json.dumps(readers)}")
	checks.check("discovery: nvda is listed without dialing", "nvda" in names, detail=str(names))

	session = _connect(server, console, mode)
	caps = session.get("capabilities", [])
	checks.check("handshake: announce capability present", "announce" in caps, detail=str(caps))

	after = set(server.tool_names())
	gated_expected = {
		"announce",
		"get_braille",
		"get_speech",
		"get_last_speech",
		"get_next_speech_index",
		"wait_for_speech",
		"wait_for_speech_to_finish",
		"press_gesture",
	}
	checks.check(
		"gating: the gated set appears after connect", gated_expected <= after, detail=str(sorted(after))
	)
	introspection = {"get_focus_info", "get_state", "get_config", "set_config"}
	checks.check(
		"gating: unannounced introspection tools stay hidden (that is 11.1)",
		not (introspection & after),
		detail=str(sorted(introspection & after)),
	)

	info = server.resource("screenreader://info")
	checks.check(
		"screenreader://info matches the handshake",
		info.get("reader") == session.get("reader") and sorted(info.get("capabilities", [])) == sorted(caps),
		detail=json.dumps(info),
	)

	text = DEFAULT_ANNOUNCE
	console.step(f'announcing (you should HEAR it): "{text}"')
	said = server.tool("announce", {"text": text})
	checks.check("announce result echoes the text", said.get("announced") == text, detail=str(said))
	checks.ear(
		"announce is HEARD aloud in NVDA's real voice (two beeps, then the message)",
		console.confirm("Did you hear the announcement spoken?"),
	)

	_disconnect(server, console)


def scenario_capture(server, console, checks, mode):
	_connect(server, console, mode)
	console.pause("Focus a BROWSE-MODE document (e.g. a web page in your browser)")

	bookmark = server.tool("get_next_speech_index")["index"]
	console.step(f"bookmarked speech index {bookmark}; opening the Elements List (NVDA+f7)")
	server.tool("press_gesture", {"gestures": ["kb:NVDA+f7"]})
	server.tool("wait_for_speech_to_finish", {"timeout": 3})

	got = server.tool("get_speech", {"since_index": bookmark})
	console.note(f"captured since {bookmark}: {json.dumps(got, ensure_ascii=False)}")
	# Each utterance is its own entry so it can carry its own logPosition.
	checks.check(
		"capture: speech since the bookmark is non-empty",
		bool(got.get("entries")),
		detail=json.dumps(got, ensure_ascii=False),
	)
	checks.check(
		"capture: every utterance carries a logPosition into the journal",
		all("logPosition" in e for e in got.get("entries", [])),
		detail=json.dumps(got.get("entries", []), ensure_ascii=False),
	)
	checks.check(
		"capture: the range starts exactly at the bookmark", got.get("fromIndex") == bookmark, detail=str(got)
	)
	checks.ear(
		"the Elements List opened and NVDA spoke it",
		console.confirm("Did the Elements List open and get announced?"),
	)

	first = server.tool("get_speech", {"since_index": bookmark})
	second = server.tool("get_speech", {"since_index": first["toIndex"]})
	checks.check(
		"ranges: [a,b) then [b,c) -- the toIndex of one is the fromIndex of the next",
		first["toIndex"] == second["fromIndex"],
		detail=f"{first['toIndex']} vs {second['fromIndex']}",
	)

	# A wait for absent text must time out and leave the session working.
	console.step("waiting 2s for text that is not there (should time out, not disconnect)")
	missing = server.tool("wait_for_speech", {"text": "zzz-not-spoken-zzz", "timeout": 2})
	checks.check(
		"wait_for_speech for absent text returns found:false",
		missing.get("found") is False,
		detail=str(missing),
	)
	still_alive = server.tool("get_last_speech")
	checks.check(
		"the session still answers after the timeout", "index" in still_alive, detail=str(still_alive)
	)

	server.tool("press_gesture", {"gestures": ["kb:escape"]})  # close the list
	_disconnect(server, console)


def scenario_braille(server, console, checks, mode):
	_connect(server, console, mode)
	console.pause("Focus any control that shows on your braille display (or read anyway)")

	speech_idx = server.tool("get_next_speech_index")["index"]
	braille = server.tool("get_braille", {"since_index": 0})
	console.note(f"braille since 0: {json.dumps(braille, ensure_ascii=False)}")
	checks.check("braille: the display content is returned", "text" in braille, detail=str(braille))
	checks.check(
		"braille: its indices are their own space, not the speech indices",
		braille.get("toIndex") != speech_idx or braille.get("fromIndex") == 0,
		detail=f"braille toIndex={braille.get('toIndex')} speech next={speech_idx}",
	)
	checks.ear(
		"the braille text matches what is on your display",
		console.confirm(f"Braille read: {braille.get('text')!r} -- does that match your display?"),
	)
	_disconnect(server, console)


def scenario_finddialog(server, console, checks, mode):
	_connect(server, console, mode)
	console.pause("Focus a BROWSE-MODE document with findable text (e.g. a web page)")

	bookmark = server.tool("get_next_speech_index")["index"]
	console.step("opening EnhancedFindDialog (NVDA+control+f)")
	server.tool("press_gesture", {"gestures": ["kb:NVDA+control+f"]})
	server.tool("wait_for_speech_to_finish", {"timeout": 3})
	opened = server.tool("get_speech", {"since_index": bookmark})
	console.note(f"on open: {json.dumps(opened, ensure_ascii=False)}")
	checks.check(
		"finddialog: opening it produced speech", bool(opened.get("entries")), detail=json.dumps(opened)
	)
	# Unless focus is confirmed, a dialog that never opened gets typed into the document.
	focus = server.tool("get_focus_info")
	console.note(f"focus after opening: {json.dumps(focus, ensure_ascii=False)}")
	in_field = focus.get("role") == "EDITABLETEXT"
	checks.check(
		"finddialog: the search field took focus (nothing is typed unless it did)",
		in_field,
		detail=json.dumps(focus, ensure_ascii=False),
	)
	if not in_field:
		console.note("!! no edit field focused -- typing NOTHING and giving up on this scenario")
		_disconnect(server, console)
		return

	term = console.ask("Type a search term the page contains", default="the")
	console.step(f'typing "{term}" and searching')
	# The field remembers the last search, so clear it and prove it is clear.
	server.tool("press_gesture", {"gestures": ["kb:control+a", "kb:delete"]})
	time.sleep(0.3)
	cleared = server.tool("get_focus_info").get("value")
	checks.check("finddialog: the field was cleared before typing", not cleared, detail=repr(cleared))
	for ch in term:
		server.tool("press_gesture", {"gestures": [f"kb:{ch}"]})
	time.sleep(0.3)
	in_box = server.tool("get_focus_info").get("value")
	console.note(f"field now holds: {in_box!r}")
	checks.check(
		"finddialog: the term reached the field intact",
		in_box == term,
		detail=f"expected {term!r}, got {in_box!r}",
	)
	mark2 = server.tool("get_next_speech_index")["index"]
	server.tool("press_gesture", {"gestures": ["kb:enter"]})
	server.tool("wait_for_speech_to_finish", {"timeout": 3})
	result = server.tool("get_speech", {"since_index": mark2})
	console.note(f"on search: {json.dumps(result, ensure_ascii=False)}")
	checks.check(
		"finddialog: submitting the search produced speech", bool(result.get("entries")), detail=str(result)
	)
	checks.ear(
		"the search moved to a match and NVDA read it",
		console.confirm("Did it jump to a match and announce it?"),
	)
	_disconnect(server, console)


def scenario_lifecycle(server, console, checks, mode):
	_connect(server, console, mode)
	console.step("disconnecting")
	server.tool("disconnect_reader")

	after = set(server.tool_names())
	checks.check(
		"disconnect: the gated tools are retracted", "get_speech" not in after, detail=str(sorted(after))
	)
	try:
		server.tool("get_speech", {"since_index": 0})
		checks.check("a gated call after disconnect is refused", False, detail="it was accepted")
	except RuntimeError as exc:
		checks.check(
			"a gated call after disconnect is refused with 'connect first'",
			"connect" in str(exc).lower(),
			detail=str(exc),
		)

	console.step("reconnecting on the same bridge")
	session = _connect(server, console, mode)
	checks.check(
		"reconnect: a second session handshakes cleanly",
		session.get("reader") == "nvda",
		detail=str(session.get("reader")),
	)

	status = server.tool("status")
	checks.check(
		"status is proven live on the wire",
		status.get("state") == "connected" and status.get("live") is True,
		detail=str(status),
	)
	_disconnect(server, console)


def scenario_log(server, console, checks, mode):
	"""Runs at `debug`: at INFO, NVDA never creates the records a gesture's span should hold."""
	_connect(server, console, mode, log_level="debug")
	console.note(f"journal ring holds {JOURNAL_MAX_RECORDS} records or 4 MiB, whichever comes first")

	console.step("item 1: pressing NVDA+t (report title), then reading that command's span alone")
	server.tool("announce", {"text": "Item one. Reading a gesture's own log span."})
	server.tool("press_gesture", {"gestures": ["kb:NVDA+t"]})
	# A span closes at the next command, so give NVDA time to finish the gesture's work first.
	time.sleep(1.5)
	span = server.tool("get_log", {"maxEntries": 400})
	console.note(
		f"span: entries={span.get('entries')} matched={span.get('matched')} "
		f"commandId={span.get('fromCommandId')} level={span.get('capturedAtLevel')}"
	)
	console.note("---- span text ----\n" + str(span.get("text", ""))[:2000])
	text = str(span.get("text", ""))
	checks.check(
		"item 1: the span is anchored on a command, not on a position",
		span.get("fromCommandId") is not None,
		detail=str(span.get("fromCommandId")),
	)
	checks.check(
		"item 1: the span holds MORE than inputCore -- NVDA's own work is attributed to the gesture",
		_has_beyond_input_core(text),
		detail=f"modules seen: {sorted(_modules(text))}",
	)
	checks.check(
		"item 1: speech records are among them (this is what 11.4 could not do)",
		any(word in text.lower() for word in ("speak", "speech")),
		detail=f"modules seen: {sorted(_modules(text))}",
	)

	console.step("item 2: marking the journal, then ten seconds of activity")
	server.tool("announce", {"text": "Item two. Marking the log, then ten seconds of activity."})
	mark = server.tool("get_log_position")
	console.note(f"mark: {mark}")
	checks.check(
		"item 2: get_log_position returns a position and a wall clock, and NO records",
		isinstance(mark.get("position"), int) and bool(mark.get("time")) and "text" not in mark,
		detail=str(mark),
	)
	console.pause("Work NVDA by hand for ten seconds (arrow around, read a line)")
	_busy_for(console, seconds=10)
	since = server.tool("get_log", {"sincePosition": mark["position"], "maxEntries": 500})
	console.note(f"since mark: entries={since.get('entries')} next={since.get('nextPosition')}")
	checks.check(
		"item 2: reading from the mark returns the records from those seconds",
		since.get("entries", 0) > 0,
		detail=str(since.get("entries")),
	)
	checks.check(
		"item 2: a position read is attributable to no single command",
		since.get("fromCommandId") is None and since.get("toCommandId") is None,
		detail=f"{since.get('fromCommandId')}..{since.get('toCommandId')}",
	)

	console.step("item 3: polling three times, each from the previous nextPosition")
	server.tool("announce", {"text": "Item three. Polling the log three times."})
	start = server.tool("get_log_position")["position"]
	polls = []
	for round_ in range(3):
		_busy_for(console, seconds=2, quiet=True)
		anchor = start if not polls else polls[-1]["nextPosition"]
		got = server.tool("get_log", {"sincePosition": anchor, "maxEntries": 500})
		console.note(f"  poll {round_ + 1}: from {anchor} -> {got['nextPosition']}, {got['entries']} entries")
		polls.append(got)
	checks.check(
		"item 3: each poll starts exactly where the last one stopped (no gap, no overlap)",
		all(polls[i]["nextPosition"] <= polls[i + 1]["nextPosition"] for i in range(len(polls) - 1)),
		detail=str([p["nextPosition"] for p in polls]),
	)
	whole = server.tool("get_log", {"sincePosition": start, "maxEntries": 2000})
	stitched = [line for p in polls for line in str(p.get("text", "")).splitlines()]
	whole_lines = str(whole.get("text", "")).splitlines()
	checks.check(
		"item 3: the three slices stitch back into the single read -- no record twice, none skipped",
		whole_lines[: len(stitched)] == stitched,
		detail=f"stitched {len(stitched)} lines, whole read {len(whole_lines)}",
	)

	console.step("item 4: the same sincePosition twice, with a different exclude in between")
	server.tool("announce", {"text": "Item four. Proving a read consumes nothing."})
	first = server.tool("get_log", {"sincePosition": start, "maxEntries": 20})
	filtered = server.tool("get_log", {"sincePosition": start, "maxEntries": 20, "exclude": ["input"]})
	again = server.tool("get_log", {"sincePosition": start, "maxEntries": 20})
	checks.check(
		"item 4: re-reading the same position returns the same records -- nothing was consumed",
		first.get("text") == again.get("text"),
		detail=f"{first.get('entries')} then {again.get('entries')} entries",
	)
	checks.check(
		"item 4: the excluded read is the same records RE-FILTERED, not a different stretch",
		filtered.get("entries", 0) <= first.get("entries", 0)
		and not any("input" in line.lower() for line in str(filtered.get("text", "")).splitlines()),
		detail=f"{first.get('entries')} unfiltered vs {filtered.get('entries')} excluding 'input'",
	)

	console.step("item 5: lastSeconds:10 right after something audible, with no prior mark")
	server.tool("announce", {"text": "Item five. Reading the last ten seconds with no mark."})
	server.tool("press_gesture", {"gestures": ["kb:NVDA+t"]})
	time.sleep(1.5)
	recent = server.tool("get_log", {"lastSeconds": 10, "maxEntries": 500})
	console.note(f"lastSeconds 10: entries={recent.get('entries')} next={recent.get('nextPosition')}")
	checks.check(
		"item 5: lastSeconds returns the records for what just happened",
		recent.get("entries", 0) > 0,
		detail=str(recent.get("entries")),
	)
	checks.check(
		"item 5: and it, too, is attributed to no single command",
		recent.get("fromCommandId") is None,
		detail=str(recent.get("fromCommandId")),
	)
	wide = server.tool("get_log", {"lastSeconds": 120, "maxEntries": 2000})
	checks.check(
		"item 5: a 10 s window is a strict subset of a 120 s one (the clock arithmetic is real)",
		recent.get("matched", 0) <= wide.get("matched", 0),
		detail=f"10s matched {recent.get('matched')}, 120s matched {wide.get('matched')}",
	)

	console.step("item 6: wait_for_log wakes at the moment a matching record lands")
	server.tool("announce", {"text": "Item six. Waiting for a log record to arrive."})
	try:
		server.tool("wait_for_log", {"timeout": 2})
		checks.check("item 6: a filterless wait is refused", False, detail="it was accepted")
	except RuntimeError as exc:
		checks.check(
			"item 6: a filterless wait is refused rather than waking on the reader's own noise",
			"filter" in str(exc).lower() or "contains" in str(exc).lower(),
			detail=str(exc),
		)
	# wait_for_log blocks the session thread, so what it waits for must come from outside the bridge.
	threading.Timer(3.0, _tap_f13, kwargs={"count": 1}).start()
	began = time.monotonic()
	woke = server.tool("wait_for_log", {"contains": ["f13"], "timeout": 20}, timeout=40)
	elapsed = time.monotonic() - began
	console.note(f"wait_for_log returned after {elapsed:.1f}s: {json.dumps(woke, ensure_ascii=False)}")
	checks.check(
		"item 6: it found the record that landed while it waited",
		woke.get("found") is True,
		detail=str(woke),
	)
	checks.check(
		"item 6: it returned AT THE MOMENT (about 3 s), not at the 20 s timeout",
		woke.get("found") is True and elapsed < 10,
		detail=f"{elapsed:.1f}s",
	)
	around = server.tool("get_log", {"sincePosition": max(0, woke.get("position", 1) - 1), "maxEntries": 30})
	checks.check(
		"item 6: the position it returned is usable as a sincePosition anchor",
		around.get("entries", 0) > 0,
		detail=str(around.get("entries")),
	)
	# A healthy session logs no errors, so this wait must end in a clean miss.
	quiet = server.tool("wait_for_log", {"min_level": "error", "timeout": 5}, timeout=25)
	checks.check(
		"item 6: an error-level wait is not woken by ordinary debug traffic",
		quiet.get("found") is False and isinstance(quiet.get("position"), int),
		detail=str(quiet),
	)
	console.note("   (a REAL error waking the wait is the `logerror` and `logwatch` scenarios)")

	console.step("item 7: trying to out-run the ring, to see truncated:true rather than a gap")
	server.tool("announce", {"text": "Item seven. Trying to overflow the log ring."})
	behind = server.tool("get_log_position")["position"]
	advanced = _flood(console, server, budget=120.0)
	# maxEntries is above the ring's capacity, so the cap cannot be what truncates this.
	stale = server.tool("get_log", {"sincePosition": behind, "maxEntries": JOURNAL_MAX_RECORDS * 2})
	console.note(
		f"journal advanced {advanced} positions past the mark; reading from it: "
		f"truncated={stale.get('truncated')} entries={stale.get('entries')} matched={stale.get('matched')}"
	)
	if advanced > JOURNAL_MAX_RECORDS:
		checks.check(
			"item 7: a poll that fell behind the ring says truncated:true, and not because of maxEntries",
			stale.get("truncated") is True and stale.get("matched", 0) <= stale.get("entries", 0),
			detail=str({k: stale.get(k) for k in ("truncated", "entries", "matched", "nextPosition")}),
		)
	else:
		checks.ear(
			f"item 7: the ring did not turn over ({advanced} records vs {JOURNAL_MAX_RECORDS} capacity) "
			f"-- eviction stays covered headlessly",
			None,
		)
	capped = server.tool("get_log", {"sincePosition": behind, "maxEntries": 5})
	checks.check(
		"item 7: truncated:true also when more matched than were returned (the other cause)",
		capped.get("truncated") is True and capped.get("matched", 0) > capped.get("entries", 0),
		detail=f"matched {capped.get('matched')}, returned {capped.get('entries')}",
	)

	server.tool("announce", {"text": "Items one to seven finished. Disconnecting."})
	_disconnect(server, console)


def scenario_logerror(server, console, checks, mode):
	"""The agent causes a real NVDA error and its own wait wakes on it.

	Keystrokes are typed with `type_text` from inside NVDA: SendInput into NVDA's console is blocked by
	UIPI, because NVDA runs with UIAccess, and the call still reports success. wait_for_log blocks the
	session thread, so the console schedules the error a few seconds out.
	"""
	_connect(server, console, mode, log_level="debug")
	server.tool("announce", {"text": "Item six. Causing a real error to wake a waiting agent."})

	console.step("opening the NVDA Python console (NVDA+control+z)")
	server.tool("press_gesture", {"gestures": ["kb:NVDA+control+z"]})
	time.sleep(1.5)
	focus = server.tool("get_focus_info")
	console.note(f"focus after opening: {json.dumps(focus, ensure_ascii=False)}")
	# All three conditions, since any one alone also matches an ordinary text field.
	on_console = (
		focus.get("appModule") == "nvda"
		and focus.get("role") == "EDITABLETEXT"
		and ">>>" in str(focus.get("name", ""))
	)
	checks.check(
		"item 6: the Python console took focus (nothing is typed unless it did)",
		on_console,
		detail=json.dumps(focus, ensure_ascii=False),
	)
	if not on_console:
		console.note("!! console did not take focus -- typing NOTHING and giving up on this item")
		server.tool("announce", {"text": "The console did not open. Nothing was typed."})
		_disconnect(server, console)
		return

	marker = "nvdaMcpBridge 0021 live error check"
	delay = 3
	# `log` is already in the console's namespace (NVDA source/pythonConsole.py).
	line = f"import threading; threading.Timer({delay}, lambda: log.error({marker!r})).start()"
	console.step(f"typing a line that logs an error {delay}s from now, then waiting for it")
	# The console keeps its input across openings, and a SyntaxError goes to the console's output,
	# not the log, so the wait would time out with nothing saying why.
	server.tool("press_gesture", {"gestures": ["kb:control+a", "kb:delete"]})
	time.sleep(0.4)
	cleared = server.tool("get_focus_info").get("value")
	console.note(f"prompt after clearing: {cleared!r}")
	checks.check("item 6: the prompt was cleared before typing", not cleared, detail=repr(cleared))

	typed = server.tool("type_text", {"text": line})
	time.sleep(0.4)
	on_prompt = server.tool("get_focus_info").get("value")
	console.note(f"typed {typed.get('typed')} characters; prompt now: {on_prompt!r}")
	checks.check(
		"item 6: type_text put the line on the prompt intact",
		on_prompt == line,
		detail=f"expected {line!r}, got {on_prompt!r}",
	)
	server.tool("press_gesture", {"gestures": ["kb:enter"]})
	time.sleep(0.4)
	after_enter = server.tool("get_focus_info").get("value")
	console.note(f"prompt after enter: {after_enter!r}")
	checks.check(
		"item 6: enter submitted the line (the prompt is empty again)",
		not after_enter,
		detail=repr(after_enter),
	)

	began = time.monotonic()
	woke = server.tool("wait_for_log", {"min_level": "error", "timeout": 20}, timeout=40)
	elapsed = time.monotonic() - began
	console.note(f"wait_for_log returned after {elapsed:.1f}s: {json.dumps(woke, ensure_ascii=False)}")
	checks.check(
		"item 6: a REAL error at ERROR level wakes the wait",
		woke.get("found") is True,
		detail=str(woke),
	)
	checks.check(
		"item 6: it woke AT the error, not at the timeout",
		woke.get("found") is True and elapsed < 15,
		detail=f"{elapsed:.1f}s",
	)
	around = server.tool("get_log", {"sincePosition": max(0, woke.get("position", 1) - 1), "maxEntries": 20})
	console.note("---- log from the error onward ----\n" + str(around.get("text", ""))[:1200])
	checks.check(
		"item 6: the returned position anchors a get_log onto OUR error",
		marker in str(around.get("text", "")),
		detail=str(around.get("text"))[:400],
	)

	console.step("closing the Python console")
	server.tool("press_gesture", {"gestures": ["kb:escape"]})
	server.tool("announce", {"text": "Item six finished. The console is closed."})
	_disconnect(server, console)


def scenario_logwatch(server, console, checks, mode):
	"""The human provokes an error inside a 60 s window while the agent waits.

	The Python console (NVDA menu, Tools) with `log.error("anything")` is the reliable way.
	"""
	_connect(server, console, mode, log_level="debug")
	window = 60
	console.step(f"waiting up to {window}s for an ERROR-level record -- provoke one NOW")
	server.tool(
		"announce",
		{"text": f"Watching the log for an error for {window} seconds. Please cause one now."},
	)
	began = time.monotonic()
	woke = server.tool("wait_for_log", {"min_level": "error", "timeout": window}, timeout=window + 30)
	elapsed = time.monotonic() - began
	console.note(f"after {elapsed:.1f}s: {json.dumps(woke, ensure_ascii=False)}")
	checks.check(
		"item 6: a REAL error, provoked by the human, wakes the waiting agent",
		woke.get("found") is True,
		detail=str(woke),
	)
	if woke.get("found"):
		server.tool("announce", {"text": "Caught it. Reading the log around the error."})
		checks.check(
			"item 6: it woke AT the error, not at the timeout",
			elapsed < window - 2,
			detail=f"{elapsed:.1f}s of a {window}s window",
		)
		around = server.tool(
			"get_log", {"sincePosition": max(0, woke.get("position", 1) - 1), "maxEntries": 20}
		)
		console.note("---- log from the error onward ----\n" + str(around.get("text", ""))[:1500])
		checks.check(
			"item 6: the returned position anchors a get_log onto the error itself",
			around.get("entries", 0) > 0,
			detail=str(around.get("entries")),
		)
	else:
		server.tool("announce", {"text": "No error arrived in the window."})
	_disconnect(server, console)


def scenario_logsilent(server, console, checks, mode):
	"""Forced silent: the suppression markers and a suppressed utterance's logPosition exist only then."""
	del mode  # this scenario is about silent capture; the flag cannot apply
	nvda_log = _nvda_log_path()
	before = _read_text(nvda_log)
	console.note(f"NVDA's own log: {nvda_log} ({len(before)} bytes before this session)")

	_connect(server, console, "silent", log_level="debug")
	server.tool("announce", {"text": "Silent session. You will hear me, but not NVDA."})

	console.step("item 9: taking a speech entry's logPosition and reading the journal around it")
	mark = server.tool("get_log_position")["position"]
	server.tool("press_gesture", {"gestures": ["kb:NVDA+t"]})
	server.tool("wait_for_speech_to_finish", {"timeout": 5})
	last = server.tool("get_last_speech")
	console.note(f"last speech (captured, NOT spoken): {json.dumps(last, ensure_ascii=False)}")
	checks.check(
		"item 9: speech was captured even though it was suppressed",
		bool(last.get("text")),
		detail=json.dumps(last, ensure_ascii=False),
	)
	checks.check(
		"item 9: the utterance carries a journal coordinate",
		isinstance(last.get("logPosition"), int) and last["logPosition"] >= mark,
		detail=f"logPosition={last.get('logPosition')} mark={mark}",
	)
	around = server.tool("get_log", {"sincePosition": mark, "maxEntries": 400})
	body = str(around.get("text", ""))
	console.note("---- journal around the utterance ----\n" + body[:2000])
	checks.check(
		"item 9: the events surrounding the suppressed utterance ARE in the journal",
		around.get("entries", 0) > 0 and _has_beyond_input_core(body),
		detail=f"modules seen: {sorted(_modules(body))}",
	)
	# Suppressing speech also stops NVDA's own "Speaking" line, so logPosition is the only link.
	checks.check(
		"item 9: and the utterance's OWN record is absent -- which is why the coordinate exists",
		not any("speech" in module for module in _modules(body)),
		detail=f"modules seen: {sorted(_modules(body))}",
	)
	checks.ear(
		"item 9: repeat with a braille entry's logPosition (needs a display or the braille viewer)",
		None,
	)

	server.tool("announce", {"text": "Ending the silent session. Speech should come back."})
	_disconnect(server, console)
	time.sleep(1.0)

	after = _read_text(nvda_log)
	added = after[len(before) :] if after.startswith(before[: min(len(before), 4096)]) else after
	suppressed = added.count(SUPPRESSED_MARKER)
	restored = added.count(RESTORED_MARKER)
	console.note(f"markers added by this session: {suppressed} suppressed, {restored} restored")
	checks.check(
		"item 8: exactly one 'speech suppressed' marker for the session",
		suppressed == 1,
		detail=f"{suppressed} found",
	)
	checks.check(
		"item 8: exactly one 'speech restored' marker, so the pair balances",
		restored == 1,
		detail=f"{restored} found",
	)
	checks.check(
		"item 8: nothing is logged per utterance",
		suppressed + restored == added.count("nvdaMcpBridge: speech"),
		detail=f"{added.count('nvdaMcpBridge: speech')} bridge speech lines in total",
	)
	checks.ear(
		"item 8: NVDA speaks again now that the session ended",
		console.confirm("Is NVDA audible again?"),
	)


#: Mirrors domain/entities/log_journal.py; used only to judge whether a flood could turn the ring over.
JOURNAL_MAX_RECORDS = 10_000

SUPPRESSED_MARKER = "nvdaMcpBridge: speech suppressed for this session"
RESTORED_MARKER = "nvdaMcpBridge: speech restored for this session"

VK_F13 = 0x7C


def _tap_f13(count: int = 1) -> None:
	"""F13 at the OS level: no application binds it, and NVDA still journals the gesture."""
	import ctypes

	user32 = ctypes.windll.user32  # type: ignore[attr-defined]
	for _ in range(count):
		user32.keybd_event(VK_F13, 0, 0, 0)
		user32.keybd_event(VK_F13, 0, 2, 0)  # KEYEVENTF_KEYUP
		time.sleep(0.002)


def _type_externally(text: str) -> None:
	"""KEYEVENTF_UNICODE delivers the character itself, independent of the keyboard layout."""
	import ctypes
	from ctypes import wintypes

	class _KeyInput(ctypes.Structure):
		_fields_ = [
			("wVk", wintypes.WORD),
			("wScan", wintypes.WORD),
			("dwFlags", wintypes.DWORD),
			("time", wintypes.DWORD),
			("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
		]

	class _Input(ctypes.Structure):
		class _Union(ctypes.Union):
			# ctypes requires a real list here; ClassVar would not be one.
			_fields_ = [("ki", _KeyInput)]

		_anonymous_ = ("u",)
		_fields_ = [("type", wintypes.DWORD), ("u", _Union)]

	user32 = ctypes.windll.user32  # type: ignore[attr-defined]
	keyeventf_keyup, keyeventf_unicode, vk_return = 0x0002, 0x0004, 0x0D

	def send(vk: int, scan: int, flags: int) -> None:
		event = _Input(type=1, u=_Input._Union(ki=_KeyInput(vk, scan, flags, 0, None)))
		user32.SendInput(1, ctypes.byref(event), ctypes.sizeof(event))

	for char in text:
		if char == "\r":
			send(vk_return, 0, 0)
			send(vk_return, 0, keyeventf_keyup)
		else:
			send(0, ord(char), keyeventf_unicode)
			send(0, ord(char), keyeventf_unicode | keyeventf_keyup)
		time.sleep(0.01)


def _busy_for(console, seconds: float, quiet: bool = False) -> None:
	if not quiet:
		console.note(f"   generating {seconds:.0f}s of activity")
	deadline = time.monotonic() + seconds
	while time.monotonic() < deadline:
		_tap_f13(5)
		time.sleep(0.25)


def _flood(console, server, budget: float) -> int:
	"""Adaptive, because the record rate depends on the machine and what has focus."""
	start = server.tool("get_log_position")["position"]
	began = time.monotonic()
	advanced = 0
	while time.monotonic() - began < budget:
		_tap_f13(40)
		advanced = server.tool("get_log_position")["position"] - start
		if advanced > JOURNAL_MAX_RECORDS:
			break
	elapsed = time.monotonic() - began
	console.note(f"   flooded for {elapsed:.0f}s: journal advanced {advanced} positions")
	return advanced


def _modules(text: str) -> set[str]:
	found = set()
	for line in text.splitlines():
		parts = line.split(" - ", 2)
		if len(parts) >= 2:
			found.add(parts[1].split(" (")[0].strip())
	return found


def _has_beyond_input_core(text: str) -> bool:
	"""A span holding only inputCore.executeGesture closed before NVDA did the work."""
	return bool({m for m in _modules(text) if m and not m.startswith("inputCore")})


def _nvda_log_path() -> str:
	return os.path.join(os.environ.get("TEMP", ""), "nvda.log")


def _read_text(path: str) -> str:
	try:
		with open(path, encoding="utf-8", errors="replace") as handle:
			return handle.read()
	except OSError:
		return ""


def scenario_persona(server, console, checks, mode):
	console.step("connecting as each persona in turn")

	for persona in ("user", "validator", "expert"):
		console.note(f"--- {persona} ---")
		console.pause(f"listen for TWO ASCENDING TONES then 'MCP session open, as {persona}'")
		session = _connect(server, console, mode, persona=persona)

		checks.check(
			f"connect as {persona}: the declaration comes back",
			session.get("persona") == persona,
			detail=f"persona={session.get('persona')!r}",
		)
		stance = session.get("stance") or ""
		checks.check(
			f"connect as {persona}: the stance rides along, in full",
			len(stance) > 200,
			detail=f"{len(stance)} chars",
		)

		reported = server.tool("status").get("session", {}).get("persona")
		checks.check(
			f"status reports {persona}",
			reported == persona,
			detail=f"status said {reported!r}",
		)

		info = server.resource("screenreader://info")
		checks.check(
			f"screenreader://info reports {persona}",
			info.get("persona") == persona,
			detail=f"info said {info.get('persona')!r}",
		)

		log_path = session.get("logPath") or ""
		wrote_it = False
		try:
			with open(log_path, encoding="utf-8", errors="replace") as handle:
				wrote_it = any("SESSION OPEN" in line and f"persona={persona}" in line for line in handle)
		except OSError as exc:
			console.note(f"could not read the transcript at {log_path}: {exc}")
		checks.check(
			f"the bridge's transcript names {persona}",
			wrote_it,
			detail=f"looked for 'persona={persona}' in {log_path}",
		)

		checks.ear(
			f"HEARD: two ascending tones, then 'MCP session open, as {persona}' ({mode} mode)",
			console.confirm(f"did you hear the tones and then 'as {persona}'?"),
		)
		_disconnect(server, console)

	console.step("refusing what is not a persona")
	try:
		server.tool("connect_reader", {"reader": "nvda", "mode": mode, "persona": "tester"})
		checks.check("an unknown persona is refused", False, detail="it was accepted")
	except RuntimeError as exc:
		message = str(exc)
		checks.check(
			"an unknown persona is refused, and the error teaches the three",
			all(name in message for name in ("user", "validator", "expert")),
			detail=message,
		)


def _gesture_for(document, command):
	"""Keyed on the command id, because the description arrives in NVDA's language."""
	for line in document.splitlines():
		cells = [cell.strip() for cell in line.split("|")]
		if len(cells) < 5 or cells[2] != f"`{command}`":
			continue
		keys = cells[3]
		if not keys.startswith("`"):
			return None
		return keys.split(",")[0].strip().strip("`")
	return None


def scenario_guidance(server, console, checks, mode):
	"""The persona documents are read from disk at run time, so only this proves they were packaged."""
	console.step("the reader's own guidance, per persona")

	seen = {}
	for persona in ("user", "validator", "expert"):
		console.note(f"--- {persona} ---")
		session = _connect(server, console, mode, persona=persona)

		checks.check(
			f"connect as {persona}: the reader's document is named in the result",
			session.get("readerGuidance") == "screenreader://reader-guidance",
			detail=f"readerGuidance={session.get('readerGuidance')!r}",
		)
		checks.check(
			"the installed bridge announces the `guidance` capability",
			"guidance" in (session.get("capabilities") or []),
			detail=f"capabilities={session.get('capabilities')}",
		)

		document = server.resource("screenreader://reader-guidance").get("text", "")
		seen[persona] = document

		checks.check(
			f"{persona}: the server's frame names the reader and the stance",
			f"nvda's guidance for the `{persona}` stance" in document,
			detail=f"{len(document)} chars",
		)
		checks.check(
			f"{persona}: the precedence rule is in the frame",
			"the stance wins" in document,
		)
		checks.check(
			f"{persona}: the INSTALLED add-on's common section arrived",
			"The ordinary vocabulary on this reader" in document,
		)
		# The document prints this machine's own bindings, so no particular key is asserted.
		checks.check(
			f"{persona}: the gesture tables were filled in from the reader",
			"| What it does | Command | Press |" in document,
		)
		checks.check(
			f"{persona}: no unsubstituted marker reached the agent",
			"{{gestures:" not in document,
		)
		checks.check(
			f"{persona}: and the tables name real bindings rather than an apology",
			"could not be asked what is bound here" not in document,
		)

		# Press the gesture the document names and listen, proving the table is true.
		# `speakForeground` first: NVDA sorts identifiers, so it comes out as `b+nvda`, and `fromName` reads
		# the last token as the key; `title` sorts as `nvda+t` and would pass by accident.
		for command in ("speakForeground", "title"):
			gesture = _gesture_for(document, command)
			checks.check(
				f"{persona}: the document names a gesture for {command}",
				gesture is not None,
				detail=f"resolved to {gesture!r}",
			)
			if not gesture:
				continue
			checks.check(
				f"{persona}: {command}'s gesture is ordered for pressing, key last",
				not gesture.endswith("nvda"),
				detail=f"{gesture!r} -- a trailing modifier would be pressed as the key",
			)
			mark = server.tool("get_next_speech_index")["index"]
			server.tool("press_gesture", {"gestures": [gesture]})
			server.tool("wait_for_speech_to_finish", {"timeout": 3.0})
			said = [e["text"] for e in server.tool("get_speech", {"since_index": mark})["entries"]]
			checks.check(
				f"{persona}: pressing {command} makes NVDA speak -- the table is TRUE, not just present",
				any(text.strip() for text in said),
				detail=f"pressed {gesture!r}, heard {said!r}",
			)
		checks.check(
			f"{persona}: and the section for this stance",
			f"Holding the `{persona}` stance on NVDA" in document,
		)

		again = server.resource("screenreader://reader-guidance").get("text", "")
		checks.check(
			f"{persona}: reading it twice gives the same document",
			again == document,
		)
		_disconnect(server, console)

	distinct = len(set(seen.values()))
	checks.check(
		"reconnecting under another persona serves another document",
		distinct == 3,
		detail=f"the three stances produced {distinct} distinct documents",
	)

	console.step("with nothing connected")
	orphan = server.resource("screenreader://reader-guidance").get("text", "")
	checks.check(
		"with no session it explains itself rather than failing",
		"No reader is connected" in orphan and "screenreader://guidance" in orphan,
		detail=orphan[:120],
	)


#: NVDA logs every tone with its pitch, so the cap's own 880 Hz cue is judgeable without an ear.
CAP_CUE_HZ = 880

_CUE_PAIR_S = 0.6

_BEEP_LINE = re.compile(r"tones\.beep \((\d\d):(\d\d):(\d\d\.\d+)\)[^\n]*\n\s*Beep at pitch (\d+)")


def _cue_seconds(log_slice: str, hz: int) -> list[float]:
	"""One time per notice: every notice is a pair of tones, so the second is dropped."""
	times = [
		int(h) * 3600 + int(m) * 60 + float(sec)
		for h, m, sec, pitch in _BEEP_LINE.findall(log_slice)
		if int(pitch) == hz
	]
	notices: list[float] = []
	for moment in times:
		if not notices or moment - notices[-1] > _CUE_PAIR_S:
			notices.append(moment)
	return notices


def _hold(server, seconds: float, ping_every: float = 15.0) -> None:
	"""`status` refreshes the 30 s heartbeat but must not reset the silence cap."""
	deadline = time.monotonic() + seconds
	while True:
		remaining = deadline - time.monotonic()
		if remaining <= 0:
			return
		time.sleep(min(ping_every, remaining))
		server.tool("status")


def scenario_silence(server, console, checks, mode):
	"""Phase 1 narrates every 30 s against a 45 s warning through each command that speaks while acting;
	phase 2 says nothing and proves the cap still fires.
	"""
	del mode  # a live session suppresses nothing; there is no silence to bound
	nvda_log = _nvda_log_path()

	console.pause("focus a BLANK Notepad tab -- phase 1 types one character into whatever has focus")
	# Marked before the connect: the handshake writes the first suppression marker.
	session_from = len(_read_text(nvda_log))
	_connect(server, console, "silent")

	narrations = (
		(
			"pressGesture",
			lambda n: server.tool(
				"press_gesture",
				{"gestures": ["nvda+t"], "announce": f"Narration {n} of 6, carried on a gesture."},
			),
		),
		(
			"typeText",
			lambda n: server.tool(
				"type_text",
				{"text": "x", "announce": f"Narration {n} of 6, carried on typing one character."},
			),
		),
		("setLogLevel", lambda n: server.tool("set_log_level", {"level": "io" if n % 4 else "debug"})),
	)
	server.tool(
		"announce",
		{
			"text": (
				"Silence cap check. For the next three minutes I will narrate every thirty "
				"seconds through the command I am running, and you should never hear the "
				"cap warn you. Then I will deliberately go quiet, and you should."
			)
		},
	)
	console.step("phase 1: narrating every 30 s through a command's own announcement (180 s)")
	phase1_from = len(_read_text(nvda_log))
	for n in range(6):
		kind, narrate = narrations[n % len(narrations)]
		console.note(f"  narration {n + 1}/6 via {kind}")
		narrate(n + 1)
		_hold(server, 30.0)
	phase1 = _read_text(nvda_log)[phase1_from:]
	heard = _cue_seconds(phase1, CAP_CUE_HZ)
	for kind in ("pressGesture", "typeText", "setLogLevel"):
		checks.check(
			f"phase 1: narrating through {kind} never lets the cap speak",
			not heard,
			detail=(
				f"{len(heard)} cap notice(s) in a 180 s run narrated every 30 s; any one "
				"of the three failing to reset would have opened a 60 s gap and warned"
			),
		)

	console.step("phase 2: saying nothing for 100 s -- the warning and the lift are due (45/90)")
	server.tool(
		"announce",
		{
			"text": (
				"Now I go quiet on purpose. Expect a warning in forty five seconds and your "
				"speech back thirty seconds after that."
			)
		},
	)
	phase2_from = len(_read_text(nvda_log))
	quiet_started = time.time()
	_hold(server, 100.0)
	quiet = _cue_seconds(_read_text(nvda_log)[phase2_from:], CAP_CUE_HZ)
	elapsed = [round(moment - _seconds_since_midnight(quiet_started), 1) for moment in quiet]
	checks.check(
		"phase 2: silence still warns and then lifts -- the fix did not simply disable the cap",
		len(quiet) == 2,
		detail=f"cap notices at +{elapsed}s (expected two, near +45 and +90)",
	)

	console.step("phase 2: one announcement carried on a gesture must re-arm the suppression")
	rearm_from = len(_read_text(nvda_log))
	rearmed_at = time.time()
	server.tool(
		"press_gesture",
		{"gestures": ["nvda+t"], "announce": "Back to work. Speech goes quiet again now."},
	)
	_hold(server, 55.0)
	after = _read_text(nvda_log)[rearm_from:]
	rearm = _cue_seconds(after, CAP_CUE_HZ)
	elapsed = [round(moment - _seconds_since_midnight(rearmed_at), 1) for moment in rearm]
	checks.check(
		"phase 2: the re-arm is audible and the fresh window warns 45 s later",
		len(rearm) == 2,
		detail=f"cap notices at +{elapsed}s (expected the re-arm at ~0 and a warning near +45)",
	)
	checks.check(
		"phase 2: the re-arm re-registers the suppression in NVDA's own log",
		after.count(SUPPRESSED_MARKER) == 1,
		detail=f"{after.count(SUPPRESSED_MARKER)} suppression marker(s) after the announcement",
	)

	_disconnect(server, console)
	time.sleep(1.0)
	whole = _read_text(nvda_log)[session_from:]
	suppressed = whole.count(SUPPRESSED_MARKER)
	restored = whole.count(RESTORED_MARKER)
	console.note(f"markers over the whole session: {suppressed} suppressed, {restored} restored")
	checks.check(
		"every suppression ended: the markers balance across the lift and the re-arm",
		suppressed == restored == 2,
		detail=f"{suppressed} suppressed, {restored} restored (expected 2 and 2)",
	)
	checks.ear("you heard your machine again at the lift, and it went quiet after the re-arm", None)


def _seconds_since_midnight(stamp: float) -> float:
	local = time.localtime(stamp)
	return local.tm_hour * 3600 + local.tm_min * 60 + local.tm_sec + (stamp % 1)


SCENARIOS = {
	"smoke": scenario_smoke,
	"persona": scenario_persona,
	"guidance": scenario_guidance,
	"capture": scenario_capture,
	"braille": scenario_braille,
	"finddialog": scenario_finddialog,
	"lifecycle": scenario_lifecycle,
	"log": scenario_log,
	"logerror": scenario_logerror,
	"logwatch": scenario_logwatch,
	"logsilent": scenario_logsilent,
	"silence": scenario_silence,
}


def _connect(server, console, mode, log_level=None, persona="expert"):
	# A log level cannot be raised retroactively: records not created at INFO are gone.
	arguments = {"reader": "nvda", "mode": mode, "persona": persona}
	if log_level is not None:
		arguments["log_level"] = log_level
	session = server.tool("connect_reader", arguments)
	console.note(
		f"connected: {session.get('reader')} {session.get('readerVersion')} "
		f"over {session.get('endpoint')}, mode={session.get('mode')}, "
		f"synth={session.get('synth')}, caps={session.get('capabilities')}"
	)
	return session


def _disconnect(server, console):
	console.step(f"disconnecting: {server.tool('disconnect_reader')}")


def scenario_run(server, mode):
	session = server.tool("connect_reader", {"reader": "nvda", "mode": mode})
	print(f"== connected: {session.get('reader')} caps={session.get('capabilities')}")
	for line in sys.stdin:
		line = line.strip()
		if not line or line.startswith("#"):
			continue
		verb, _, arg = line.partition(" ")
		try:
			if _run_command(server, verb, arg.strip()) == "stop":
				break
		except Exception as exc:
			print(f"   !! {verb}: {exc}")
	print(f"== disconnecting: {server.tool('disconnect_reader')}")
	return 0


def _run_command(server, verb, arg):
	table = {
		"announce": lambda: server.tool("announce", {"text": arg}),
		"press": lambda: server.tool("press_gesture", {"gestures": arg.split()}),
		"bookmark": lambda: server.tool("get_next_speech_index"),
		"speech": lambda: server.tool("get_speech", {"since_index": int(arg)}),
		"lastspeech": lambda: server.tool("get_last_speech"),
		"braille": lambda: server.tool("get_braille", {"since_index": int(arg)}),
		"status": lambda: server.tool("status"),
	}
	if verb in table:
		print(f"-> {verb} {arg}: {table[verb]()}")
	elif verb == "waitspeech":
		timeout, _, text = arg.partition(" ")
		found = server.tool("wait_for_speech", {"text": text.strip(), "timeout": float(timeout)})
		print(f"-> waitspeech: {found}")
	elif verb == "sleep":
		time.sleep(float(arg))
		print(f"-> slept {arg}s")
	elif verb == "disconnect":
		return "stop"
	else:
		print(f"   ?? unknown command {verb!r}")
	return None


class Console:
	def __init__(self, auto: bool) -> None:
		self.auto = auto
		if auto:
			print(
				"[auto mode: setup pauses are skipped and audible checks are marked EAR "
				"for you to confirm by hand]"
			)

	def step(self, msg: str) -> None:
		print(f"-> {msg}")

	def note(self, msg: str) -> None:
		print(f"   {msg}")

	def pause(self, msg: str) -> None:
		if self.auto:
			print(f"[setup -- do this now] {msg}")
			time.sleep(2)
			return
		input(f"[setup] {msg}, then press Enter ... ")

	def confirm(self, msg: str):
		if self.auto:
			return None
		return input(f"[confirm] {msg} (y/n): ").strip().lower().startswith("y")

	def ask(self, msg: str, default: str) -> str:
		if self.auto:
			return default
		return input(f"[input] {msg} [{default}]: ").strip() or default


class Checklist:
	def __init__(self) -> None:
		self._rows: list[tuple[str, str, str]] = []

	def check(self, name: str, ok: bool, detail: str = "") -> None:
		self._rows.append((name, "PASS" if ok else "FAIL", "" if ok else detail))

	def ear(self, name: str, answer) -> None:
		status = "EAR" if answer is None else ("PASS" if answer else "FAIL")
		self._rows.append((name, status, ""))

	def summary(self) -> int:
		print("\n==== results ====")
		failed = 0
		ears = 0
		for name, status, detail in self._rows:
			mark = {"PASS": "[x]", "FAIL": "[ ]", "EAR": "[?]"}[status]
			line = f"{mark} {status:4} {name}"
			if detail:
				line += f"  -- {detail}"
			print(line)
			failed += status == "FAIL"
			ears += status == "EAR"
		print(
			f"---- {len(self._rows)} checks: "
			f"{sum(1 for r in self._rows if r[1] == 'PASS')} pass, {failed} fail, {ears} need your ear"
		)
		return 1 if failed else 0


class Server:
	def __init__(self, binary: str) -> None:
		self._proc = subprocess.Popen(
			[binary],
			stdin=subprocess.PIPE,
			stdout=subprocess.PIPE,
			stderr=subprocess.PIPE,
			bufsize=0,
		)
		self._lines: queue.Queue[bytes] = queue.Queue()
		self._err: list[bytes] = []
		threading.Thread(target=_pump, args=(self._proc.stdout, self._lines), daemon=True).start()
		threading.Thread(target=_drain, args=(self._proc.stderr, self._err), daemon=True).start()
		self._id = 0

	def initialize(self) -> None:
		info = self._call(
			"initialize",
			{
				"protocolVersion": "2025-06-18",
				"capabilities": {},
				"clientInfo": {"name": "live_test", "version": "0"},
			},
		).get("serverInfo", {})
		print(f"== initialized: {info.get('name')} {info.get('version')}")
		self._notify("notifications/initialized")

	def tool_names(self) -> list[str]:
		return sorted(t["name"] for t in self._call("tools/list")["tools"])

	def tool(self, name: str, arguments: dict | None = None, timeout: float = 30.0) -> dict:
		# The RPC deadline must exceed a blocking tool's own wait, or a served call reads as a hang.
		result = self._call("tools/call", {"name": name, "arguments": arguments or {}}, timeout=timeout)
		if result.get("isError"):
			raise RuntimeError("".join(c.get("text", "") for c in result.get("content", [])) or "tool failed")
		if "structuredContent" in result:
			return result["structuredContent"]
		for block in result.get("content", []):
			if block.get("type") == "text":
				try:
					return json.loads(block["text"])
				except json.JSONDecodeError:
					return {"text": block["text"]}
		return result

	def resource(self, uri: str) -> dict:
		result = self._call("resources/read", {"uri": uri})
		for item in result.get("contents", []):
			if "text" in item:
				try:
					return json.loads(item["text"])
				except json.JSONDecodeError:
					return {"text": item["text"]}
		return result

	def stderr_tail(self) -> str:
		time.sleep(0.2)
		return b"".join(self._err).decode("utf-8", "replace").strip()

	def close(self) -> None:
		try:
			self._proc.stdin.close()
		except Exception:
			pass
		self._proc.terminate()

	def _call(self, method: str, params: dict | None = None, timeout: float = 30.0) -> dict:
		self._id += 1
		my_id = self._id
		msg = {"jsonrpc": "2.0", "id": my_id, "method": method}
		if params is not None:
			msg["params"] = params
		self._send(msg)
		deadline = time.monotonic() + timeout
		while time.monotonic() < deadline:
			try:
				raw = self._lines.get(timeout=max(0.01, deadline - time.monotonic()))
			except queue.Empty:
				break
			reply = json.loads(raw)
			if reply.get("id") != my_id:
				continue
			if "error" in reply:
				raise RuntimeError(f"{method} -> {reply['error']}")
			return reply.get("result", {})
		raise TimeoutError(f"no response to {method} within {timeout}s")

	def _notify(self, method: str, params: dict | None = None) -> None:
		msg = {"jsonrpc": "2.0", "method": method}
		if params is not None:
			msg["params"] = params
		self._send(msg)

	def _send(self, msg: dict) -> None:
		self._proc.stdin.write((json.dumps(msg) + "\n").encode("utf-8"))
		self._proc.stdin.flush()


def _pump(stream, out: queue.Queue[bytes]) -> None:
	for line in stream:
		line = line.strip()
		if line:
			out.put(line)


def _drain(stream, buf: list[bytes]) -> None:
	for line in stream:
		buf.append(line)


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
