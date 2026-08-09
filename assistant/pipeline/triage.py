"""Triage engine — §5.

Classifies each message and scores urgency. Urgency deliberately reads
Contact.tier and Contact.deferral_count rather than computing its own
parallel importance signal — see the blueprint's explicit warning
against two systems ranking senders by different logic.

Calendar extraction here is a minimal keyword/regex heuristic, not an
NLP date parser — good enough to prove the pipeline shape, not good
enough for production (a real build should use a proper date-time
parsing library).
"""

from __future__ import annotations

import re
from datetime import datetime, timedelta

from ..models import Classification, Contact, Message, Tier, now
from ..store import Store

NOISE_MARKERS = ("unsubscribe", "no-reply", "noreply", "marketing", "newsletter")
TIME_PRESSURE_MARKERS = ("asap", "eod", "urgent", "by tomorrow", "by today", "right away")
REPLY_MARKERS = ("?", "let me know", "can you", "could you", "would you", "are you")

_WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
_TIME_RE = re.compile(
    r"\b(" + "|".join(_WEEKDAYS) + r")\b.{0,15}?\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b",
    re.IGNORECASE,
)

_TIER_WEIGHT = {
    Tier.T1: 100.0,
    Tier.T2: 60.0,
    Tier.T3: 30.0,
    Tier.T4: 10.0,
    Tier.UNTIERED: 10.0,
}


def classify(message: Message) -> Classification:
    body = message.body.lower()
    if any(marker in body for marker in NOISE_MARKERS):
        return Classification.NOISE
    if extract_proposed_slot(message.body) is not None:
        return Classification.NEEDS_CALENDAR
    if any(marker in body for marker in REPLY_MARKERS):
        return Classification.NEEDS_REPLY
    return Classification.FYI


def extract_proposed_slot(body: str, reference: datetime | None = None) -> tuple[float, float] | None:
    """Very small heuristic: "<weekday> <hour>[:minute][am/pm]" → a
    2-hour default slot starting there. Returns None if nothing matches."""
    match = _TIME_RE.search(body)
    if not match:
        return None
    weekday_name, hour_s, minute_s, meridiem = match.groups()
    hour = int(hour_s)
    minute = int(minute_s) if minute_s else 0
    if meridiem and meridiem.lower() == "pm" and hour != 12:
        hour += 12
    if not (0 <= hour < 24):
        return None

    reference = reference or datetime.fromtimestamp(now())
    target_weekday = _WEEKDAYS.index(weekday_name.lower())
    days_ahead = (target_weekday - reference.weekday()) % 7 or 7
    target_date = reference + timedelta(days=days_ahead)
    start = target_date.replace(hour=hour, minute=minute, second=0, microsecond=0)
    end = start + timedelta(hours=2)
    return (start.timestamp(), end.timestamp())


def score_urgency(message: Message, contact: Contact, at: float | None = None) -> float:
    at = at if at is not None else now()
    body = message.body.lower()

    time_pressure = 40.0 if any(marker in body for marker in TIME_PRESSURE_MARKERS) else 0.0

    age_hours = max(0.0, (at - message.received_at) / 3600.0)
    age_score = min(age_hours, 72.0)  # cap so a month-old message doesn't dominate forever

    tier_score = _TIER_WEIGHT[contact.tier]

    # deferral_count is the single source of truth for repeat-avoidance
    # escalation (§5B.4) — it intensifies without a plateau (§10 Q11).
    deferral_score = contact.deferral_count * 25.0

    return time_pressure + age_score + tier_score + deferral_score


def triage_message(message: Message, store: Store) -> Message:
    """Runs classification, calendar extraction, and urgency scoring
    for one message and persists the result."""
    contact = store.get_contact(message.contact_id)
    if contact is None:
        raise ValueError(f"unknown contact_id {message.contact_id!r}")

    message.classification = classify(message)
    if message.classification == Classification.NEEDS_CALENDAR:
        message.proposed_slot = extract_proposed_slot(message.body)
    message.urgency_score = score_urgency(message, contact)

    store.upsert_message(message)
    return message
