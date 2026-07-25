# nvdaMcpBridge tests -- FakeFocusInspector, standing in for the FocusInspector port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# FAKES: domain/ports/focus_inspector.py
#
# Returns a configurable FocusInfo snapshot. Defaults to a plausible focus
# (a button) so a bare roundtrip test doesn't need to seed one.

from __future__ import annotations

from nvdaMcpBridge.domain.ports.focus_inspector import FocusInfo, FocusInspector


class FakeFocusInspector(FocusInspector):
    """Returns a configurable FocusInfo; records every call."""

    def __init__(self) -> None:
        self.calls: list[None] = []
        self.info: FocusInfo = FocusInfo(
            name="Test Button",
            role="BUTTON",
            states=["FOCUSABLE", "FOCUSED"],
            value=None,
            app_module="test_app",
        )

    def focus_info(self) -> FocusInfo:
        self.calls.append(None)
        return self.info
