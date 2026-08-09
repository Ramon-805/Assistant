from assistant.models import Contact, Message, SourceType, Tier
from assistant.store import Store


def make_store() -> Store:
    return Store(":memory:")


def test_contact_roundtrip():
    store = make_store()
    c = Contact(display_name="Alice", handles=["alice@x.com"], tier=Tier.T1)
    store.upsert_contact(c)
    fetched = store.get_contact(c.id)
    assert fetched.display_name == "Alice"
    assert fetched.tier == Tier.T1
    assert fetched.handles == ["alice@x.com"]


def test_find_contact_by_handle_merges_identity():
    """§4.2 — handle resolution is the join that keeps tiers/registers
    from fragmenting across email/phone/app handles for the same person."""
    store = make_store()
    c = Contact(display_name="Alice", handles=["alice@x.com", "+15551234567"])
    store.upsert_contact(c)
    assert store.find_contact_by_handle("+15551234567").id == c.id
    assert store.find_contact_by_handle("unknown@x.com") is None


def test_thread_history_rolling_window():
    store = make_store()
    contact = Contact(display_name="Bob", handles=["bob@x.com"])
    store.upsert_contact(contact)
    for i in range(15):
        store.upsert_message(Message(
            contact_id=contact.id, source=SourceType.GMAIL, body=f"msg {i}",
            thread_id="t1", received_at=float(i),
        ))
    history = store.thread_history("t1", limit=10)
    assert len(history) == 10
    # most recent first
    assert history[0].body == "msg 14"
