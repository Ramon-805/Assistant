"""Review & dispatch — §4.1 (right-hand write-back edges), §6.4.

Three user actions, each writing back to persistent state: send (no
write-back beyond status), defer (→ Contact.deferral_count), and edit
(→ Register refinement signal). These write-backs are what the
blueprint calls the not-optional part of the pipeline.

Actually transmitting a send (Gmail/SMS API calls) is out of scope for
this scaffold — see ingestion.py for why those integrations aren't
wired up. send() here only updates local state.
"""

from __future__ import annotations

from ..models import Draft, DraftStatus
from ..store import Store
from .briefing import BriefingItem


def send(draft: Draft, store: Store) -> Draft:
    # TODO(Phase 2+): call the real Gmail/Outlook/SMS send API here,
    # or write to clipboard for notification-sourced messages (§3).
    draft.status = DraftStatus.SENT
    store.upsert_draft(draft)
    return draft


def defer(item: BriefingItem, store: Store) -> None:
    """§5B.4 — deferral escalates, it never demotes. Applies to every
    contact represented in the deferred briefing item."""
    for contact in item.contacts:
        contact.deferral_count += 1
        store.upsert_contact(contact)


def resolve(item: BriefingItem, store: Store) -> None:
    """Call when a briefing item is actually acted on (sent/dismissed),
    resetting the avoidance signal so escalation reflects current state."""
    for contact in item.contacts:
        if contact.deferral_count:
            contact.deferral_count = 0
            store.upsert_contact(contact)


def apply_edit(draft: Draft, edited_body: str, store: Store) -> Draft:
    """§6.4 — every pre-send edit is a training signal. Actually
    retraining the register's style profile from edits is future work;
    this scaffold only records that an edit happened (sample_count) so
    the accelerated-learning-for-young-registers rule (§6.2.2) has a
    real counter to key off of."""
    draft.body = edited_body
    draft.status = DraftStatus.EDITED
    store.upsert_draft(draft)

    register = store.get_register(draft.register_id)
    if register is not None:
        register.sample_count += 1
        store.upsert_register(register)

    return draft
