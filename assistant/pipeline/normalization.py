"""Normalization — §4.1.

Converts a RawMessage into a Message, resolving its handle to a
Contact. New handles get a fresh UNTIERED contact (§10 Q10 — no
default tier; the briefing prompts for assignment on first
appearance, not here).
"""

from __future__ import annotations

from ..models import Contact, Message, Tier
from ..store import Store
from .ingestion import RawMessage


def resolve_contact(handle: str, store: Store, display_name: str = "") -> Contact:
    existing = store.find_contact_by_handle(handle)
    if existing:
        return existing
    contact = Contact(display_name=display_name or handle, handles=[handle], tier=Tier.UNTIERED)
    store.upsert_contact(contact)
    return contact


def normalize(raw: RawMessage, store: Store) -> Message:
    contact = resolve_contact(raw.handle, store)
    message = Message(
        contact_id=contact.id,
        source=raw.source,
        source_app=raw.source_app,
        body=raw.body,
        received_at=raw.received_at,
        thread_id=raw.thread_id,
        is_truncated=raw.is_truncated,
        can_reply_direct=raw.can_reply_direct,
    )
    store.upsert_message(message)
    return message
