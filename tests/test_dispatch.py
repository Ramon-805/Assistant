from assistant.models import Contact, Draft, DraftStatus, Register
from assistant.pipeline.briefing import BriefingItem
from assistant.pipeline.dispatch import apply_edit, defer, resolve, send
from assistant.store import Store


def test_defer_increments_deferral_count_for_all_contacts_in_item():
    store = Store(":memory:")
    a = Contact(id="a", deferral_count=0)
    b = Contact(id="b", deferral_count=2)
    store.upsert_contact(a)
    store.upsert_contact(b)
    item = BriefingItem(cluster=None, messages=[], contacts=[a, b],
                         escalated=False, needs_tier_prompt=False, max_urgency=0.0)

    defer(item, store)

    assert store.get_contact("a").deferral_count == 1
    assert store.get_contact("b").deferral_count == 3


def test_resolve_resets_deferral_count():
    store = Store(":memory:")
    a = Contact(id="a", deferral_count=5)
    store.upsert_contact(a)
    item = BriefingItem(cluster=None, messages=[], contacts=[a],
                         escalated=True, needs_tier_prompt=False, max_urgency=0.0)

    resolve(item, store)

    assert store.get_contact("a").deferral_count == 0


def test_send_marks_draft_sent():
    store = Store(":memory:")
    d = Draft(body="hi", status=DraftStatus.PENDING)
    store.upsert_draft(d)
    send(d, store)
    assert store.list_drafts_for_decision(d.decision_id)  # persisted
    assert d.status == DraftStatus.SENT


def test_apply_edit_updates_body_status_and_register_sample_count():
    store = Store(":memory:")
    store.upsert_register(Register(id="professional", name="professional", sample_count=0))
    d = Draft(body="original", register_id="professional", status=DraftStatus.PENDING)
    store.upsert_draft(d)

    apply_edit(d, "edited body", store)

    assert d.body == "edited body"
    assert d.status == DraftStatus.EDITED
    assert store.get_register("professional").sample_count == 1
