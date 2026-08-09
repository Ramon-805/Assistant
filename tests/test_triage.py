from assistant.models import Classification, Contact, Message, Tier
from assistant.pipeline.triage import classify, extract_proposed_slot, score_urgency


def test_classify_noise():
    m = Message(body="Please unsubscribe from our newsletter")
    assert classify(m) == Classification.NOISE


def test_classify_needs_calendar():
    m = Message(body="Are you free Monday at 2pm?")
    assert classify(m) == Classification.NEEDS_CALENDAR


def test_classify_needs_reply():
    m = Message(body="Can you send me the file?")
    assert classify(m) == Classification.NEEDS_REPLY


def test_classify_fyi():
    m = Message(body="The invoice was paid.")
    assert classify(m) == Classification.FYI


def test_extract_proposed_slot_parses_weekday_and_time():
    slot = extract_proposed_slot("Are you free Monday at 2pm to chat?")
    assert slot is not None
    start, end = slot
    assert end > start


def test_extract_proposed_slot_none_when_absent():
    assert extract_proposed_slot("Are you around this week?") is None


def test_urgency_reads_contact_tier_not_its_own_model():
    """§5 — urgency must consume Contact.tier, not infer sender
    importance independently. A T1 contact should outrank an
    otherwise-identical UNTIERED one."""
    t1_contact = Contact(tier=Tier.T1)
    untiered_contact = Contact(tier=Tier.UNTIERED)
    message = Message(body="hello", received_at=0.0)

    t1_score = score_urgency(message, t1_contact, at=0.0)
    untiered_score = score_urgency(message, untiered_contact, at=0.0)
    assert t1_score > untiered_score


def test_urgency_escalates_with_deferral_count():
    base = Contact(tier=Tier.T3, deferral_count=0)
    deferred = Contact(tier=Tier.T3, deferral_count=4)
    message = Message(body="hello", received_at=0.0)
    assert score_urgency(message, deferred, at=0.0) > score_urgency(message, base, at=0.0)


def test_urgency_increases_with_age():
    contact = Contact(tier=Tier.T3)
    old = Message(body="hello", received_at=0.0)
    new = Message(body="hello", received_at=3600.0)
    at = 7200.0
    assert score_urgency(old, contact, at=at) > score_urgency(new, contact, at=at)
