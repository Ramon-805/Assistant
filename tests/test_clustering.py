import time

from assistant.models import Classification, Contact, Decision, Message
from assistant.pipeline.clustering import apply_prior_decisions, cluster_messages
from assistant.store import Store


def _contact(store: Store, id_: str, always_individual: bool = False) -> Contact:
    c = Contact(id=id_, display_name=id_, handles=[f"{id_}@x.com"], always_individual=always_individual)
    store.upsert_contact(c)
    return c


def test_calendar_conflict_clusters_overlapping_slots():
    store = Store(":memory:")
    _contact(store, "a")
    _contact(store, "b")
    slot = (1000.0, 3000.0)
    m1 = Message(contact_id="a", classification=Classification.NEEDS_CALENDAR, proposed_slot=slot)
    m2 = Message(contact_id="b", classification=Classification.NEEDS_CALENDAR, proposed_slot=slot)
    store.upsert_message(m1)
    store.upsert_message(m2)

    clusters = cluster_messages([m1, m2], store)
    assert len(clusters) == 1
    assert set(clusters[0].message_ids) == {m1.id, m2.id}


def test_same_question_clusters_similar_text():
    store = Store(":memory:")
    _contact(store, "a")
    _contact(store, "b")
    m1 = Message(contact_id="a", classification=Classification.NEEDS_REPLY,
                 body="Are you coming to the offsite Friday? Let me know.")
    m2 = Message(contact_id="b", classification=Classification.NEEDS_REPLY,
                 body="You in for the offsite Friday? Let me know.")
    store.upsert_message(m1)
    store.upsert_message(m2)

    clusters = cluster_messages([m1, m2], store)
    assert len(clusters) == 1
    assert set(clusters[0].message_ids) == {m1.id, m2.id}


def test_dissimilar_messages_are_not_clustered():
    """Under-cluster bias (§5A.3) — two unrelated NEEDS_REPLY messages
    should stay separate rather than get forced together."""
    store = Store(":memory:")
    _contact(store, "a")
    _contact(store, "b")
    m1 = Message(contact_id="a", classification=Classification.NEEDS_REPLY, body="Can you send the file?")
    m2 = Message(contact_id="b", classification=Classification.NEEDS_REPLY, body="Want to grab lunch?")
    store.upsert_message(m1)
    store.upsert_message(m2)

    clusters = cluster_messages([m1, m2], store)
    assert clusters == []


def test_always_individual_contact_excluded_from_clustering():
    store = Store(":memory:")
    _contact(store, "a", always_individual=True)
    _contact(store, "b")
    slot = (1000.0, 3000.0)
    m1 = Message(contact_id="a", classification=Classification.NEEDS_CALENDAR, proposed_slot=slot)
    m2 = Message(contact_id="b", classification=Classification.NEEDS_CALENDAR, proposed_slot=slot)
    store.upsert_message(m1)
    store.upsert_message(m2)

    clusters = cluster_messages([m1, m2], store)
    assert clusters == []


def test_apply_prior_decisions_absorbs_matching_message():
    """§5A.4 — a message proposing a slot inside an unexpired Decision's
    scope should join that decision instead of entering fresh clustering."""
    store = Store(":memory:")
    _contact(store, "a")
    decision = Decision(intent_text="I'm booked", scope={"slot": [1000.0, 3000.0]})
    store.upsert_decision(decision)

    m = Message(contact_id="a", classification=Classification.NEEDS_CALENDAR, proposed_slot=(1500.0, 2500.0))
    store.upsert_message(m)

    remaining = apply_prior_decisions([m], store, now=time.time())
    assert remaining == []
    stored = store.get_message(m.id)
    assert stored.cluster_id is not None
