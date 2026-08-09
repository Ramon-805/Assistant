from assistant.models import Contact, Decision, Message, Register
from assistant.pipeline.voice import Drafter, MockDrafter, fan_out
from assistant.store import Store


class IdenticalDrafter(Drafter):
    """Ignores the recipient entirely — the exact failure mode §5A.2
    warns about (three friends compare texts, find identical wording)."""

    def generate(self, intent, contact, register, modifier, thread_history) -> str:
        return f"Answer: {intent}"


class PerRecipientDrafter(Drafter):
    def generate(self, intent, contact, register, modifier, thread_history) -> str:
        return f"Hey {contact.display_name}, {intent} (from {register.name})"


def _setup(store: Store, ids: list[str], register_id: str | None = "professional") -> list[Message]:
    store.upsert_register(Register(id="professional", name="professional", is_mature=True))
    store.upsert_register(Register(id="social", name="social", is_mature=True))
    messages = []
    for cid in ids:
        contact = Contact(id=cid, display_name=cid, handles=[f"{cid}@x.com"], register_id=register_id)
        store.upsert_contact(contact)
        m = Message(contact_id=cid, body="are you free monday?")
        store.upsert_message(m)
        messages.append(m)
    return messages


def test_fan_out_flags_near_duplicate_within_same_register():
    store = Store(":memory:")
    messages = _setup(store, ["a", "b"])
    decision = Decision(intent_text="Sorry, can't make it")
    store.upsert_decision(decision)

    result = fan_out(decision, messages, store, IdenticalDrafter())
    assert len(result.drafts) == 2
    assert len(result.near_duplicate_pairs) == 1


def test_fan_out_no_false_positive_with_per_recipient_wording():
    store = Store(":memory:")
    messages = _setup(store, ["a", "b"])
    decision = Decision(intent_text="Sorry, can't make it")
    store.upsert_decision(decision)

    result = fan_out(decision, messages, store, PerRecipientDrafter())
    assert result.near_duplicate_pairs == []


def test_fan_out_falls_back_to_formal_register_when_unassigned():
    """§6.2.5 — uncertain register fails toward formality."""
    store = Store(":memory:")
    store.upsert_register(Register(id="formal", name="formal", is_mature=True))
    messages = _setup(store, ["a"], register_id=None)
    decision = Decision(intent_text="hi")
    store.upsert_decision(decision)

    result = fan_out(decision, messages, store, MockDrafter())
    assert result.drafts[0].register_id == "formal"


def test_fan_out_flags_register_mismatch():
    store = Store(":memory:")
    messages = _setup(store, ["a"], register_id="professional")
    decision = Decision(intent_text="hi")
    store.upsert_decision(decision)

    class SlangInProfessionalDrafter(Drafter):
        def generate(self, intent, contact, register, modifier, thread_history) -> str:
            return "yo bro let's do this, lol"

    result = fan_out(decision, messages, store, SlangInProfessionalDrafter())
    assert result.drafts[0].id in result.register_mismatch_ids


def test_fan_out_does_not_flag_cross_register_as_duplicate():
    """§6.2.4 — cross-register drafts are expected to differ; the
    near-duplicate check should only compare within the same register."""
    store = Store(":memory:")
    store.upsert_register(Register(id="professional", name="professional", is_mature=True))
    store.upsert_register(Register(id="social", name="social", is_mature=True))
    a = Contact(id="a", display_name="a", handles=["a@x.com"], register_id="professional")
    b = Contact(id="b", display_name="b", handles=["b@x.com"], register_id="social")
    store.upsert_contact(a)
    store.upsert_contact(b)
    m1 = Message(contact_id="a", body="are you free monday?")
    m2 = Message(contact_id="b", body="are you free monday?")
    store.upsert_message(m1)
    store.upsert_message(m2)
    decision = Decision(intent_text="Sorry, can't make it")
    store.upsert_decision(decision)

    result = fan_out(decision, [m1, m2], store, IdenticalDrafter())
    assert result.near_duplicate_pairs == []
