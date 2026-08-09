"""Briefing builder — §4.1, §5B.4, §10 Q10.

Produces the ordered agenda the user reviews: one entry per cluster,
plus any unclustered eligible message on its own. Contacts with 3+
deferrals are surfaced at the top regardless of urgency score — §5B.4
requires deferral to escalate, never to demote or hide.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..models import Classification, Cluster, Contact, Message, Tier
from ..store import Store

DEFERRAL_ESCALATION_THRESHOLD = 3


@dataclass
class BriefingItem:
    cluster: Cluster | None
    messages: list[Message]
    contacts: list[Contact]
    escalated: bool
    needs_tier_prompt: bool
    max_urgency: float


def build_briefing(store: Store) -> list[BriefingItem]:
    eligible = [
        m for m in store.list_messages()
        if m.classification in (Classification.NEEDS_REPLY, Classification.NEEDS_CALENDAR)
    ]
    solo = [m for m in eligible if not m.cluster_id]

    items: list[BriefingItem] = []
    for cluster in store.list_clusters():
        msgs = [store.get_message(mid) for mid in cluster.message_ids]
        msgs = [m for m in msgs if m is not None]
        if not msgs:
            continue
        contacts = [store.get_contact(m.contact_id) for m in msgs]
        contacts = [c for c in contacts if c is not None]
        items.append(_build_item(cluster, msgs, contacts))

    for m in solo:
        contact = store.get_contact(m.contact_id)
        if contact is None:
            continue
        items.append(_build_item(None, [m], [contact]))

    # Escalated items first; within each group, highest urgency first.
    items.sort(key=lambda i: (not i.escalated, -i.max_urgency))
    return items


def _build_item(cluster: Cluster | None, messages: list[Message], contacts: list[Contact]) -> BriefingItem:
    return BriefingItem(
        cluster=cluster,
        messages=messages,
        contacts=contacts,
        escalated=any(c.deferral_count >= DEFERRAL_ESCALATION_THRESHOLD for c in contacts),
        needs_tier_prompt=any(c.tier == Tier.UNTIERED for c in contacts),
        max_urgency=max((m.urgency_score for m in messages), default=0.0),
    )
