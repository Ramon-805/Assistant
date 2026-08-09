"""Ingestion — §4.1, §7 (Platform Reality Matrix).

Each source implements the same narrow interface so the rest of the
pipeline never branches on channel. Real Gmail/Outlook/SMS/Notification
sources need OAuth credentials or platform (Android) access this
environment doesn't have — they're stubbed with a clear TODO rather
than faked. MockSource is what the CLI demo runs against.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional

from ..models import SourceType, now


@dataclass
class RawMessage:
    """What a source hands to normalization, before a Contact exists."""
    handle: str  # email address, phone number, or app-reported name
    source: SourceType
    body: str
    received_at: float = field(default_factory=now)
    source_app: Optional[str] = None
    thread_id: Optional[str] = None
    is_truncated: bool = False
    can_reply_direct: bool = True


class MessageSource(ABC):
    source_type: SourceType

    @abstractmethod
    def fetch_new(self) -> list[RawMessage]:
        """Return messages since the last fetch. Idempotency/cursor
        tracking is a real-source concern, not modeled here."""


class GmailSource(MessageSource):
    source_type = SourceType.GMAIL

    def __init__(self, credentials: Optional[dict] = None):
        self.credentials = credentials

    def fetch_new(self) -> list[RawMessage]:
        # TODO(Phase 2): OAuth via Gmail API, list messages.google or
        # threads.list since last historyId, map to RawMessage.
        raise NotImplementedError(
            "GmailSource requires OAuth credentials — not wired up in this scaffold."
        )


class OutlookSource(MessageSource):
    source_type = SourceType.OUTLOOK

    def __init__(self, credentials: Optional[dict] = None):
        self.credentials = credentials

    def fetch_new(self) -> list[RawMessage]:
        # TODO(Phase 5): Microsoft Graph OAuth + /me/messages delta query.
        raise NotImplementedError(
            "OutlookSource requires OAuth credentials — not wired up in this scaffold."
        )


class SmsSource(MessageSource):
    source_type = SourceType.SMS

    def __init__(self, credentials: Optional[dict] = None):
        self.credentials = credentials

    def fetch_new(self) -> list[RawMessage]:
        # TODO(Phase 5): Android default-SMS-app role (§10.1C) or Telephony
        # content provider read. Needs an Android runtime, not available here.
        raise NotImplementedError(
            "SmsSource requires the Android default-SMS-app role — not wired up in this scaffold."
        )


class NotificationSource(MessageSource):
    """Read-only — §3 explicit non-goal forbids sending here."""

    source_type = SourceType.NOTIFICATION

    def __init__(self, credentials: Optional[dict] = None):
        self.credentials = credentials

    def fetch_new(self) -> list[RawMessage]:
        # TODO(Phase 5): Android NotificationListenerService. Bodies are
        # typically truncated — RawMessage.is_truncated should be True,
        # RawMessage.can_reply_direct should be False (draft-and-copy only).
        raise NotImplementedError(
            "NotificationSource requires an Android NotificationListenerService — "
            "not wired up in this scaffold."
        )


class MockSource(MessageSource):
    """In-memory source for local development and the CLI demo."""

    source_type = SourceType.GMAIL

    def __init__(self, messages: Optional[list[RawMessage]] = None):
        self._messages = list(messages or [])

    def add(self, message: RawMessage) -> None:
        self._messages.append(message)

    def fetch_new(self) -> list[RawMessage]:
        drained, self._messages = self._messages, []
        return drained
