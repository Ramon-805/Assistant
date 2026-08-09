"""Manual "run my brief" trigger — Phase 2 (§9): batched from day one,
no per-message prompting. This wires ingestion → normalization →
triage → prior-decision reuse → clustering → briefing → intent
capture → voice engine → review/dispatch into one runnable path,
using MockSource and MockDrafter since real integrations need
credentials this environment doesn't have (see pipeline/ingestion.py).

Run: python -m assistant.cli            (scripted walkthrough, no input needed)
     python -m assistant.cli --interactive   (prompts you for real intents)
"""

from __future__ import annotations

import argparse
import time

from .models import CalendarEvent, Contact, CommitmentClass, Decision, Register, Tier
from .pipeline.briefing import BriefingItem, build_briefing
from .pipeline.clustering import apply_prior_decisions, attach_decision, cluster_messages
from .pipeline.dispatch import defer, resolve, send
from .pipeline.displacement import decide_displacement
from .pipeline.ingestion import MockSource, RawMessage
from .pipeline.normalization import normalize
from .models import SourceType, ClusterType
from .pipeline.triage import triage_message
from .pipeline.voice import FanOutResult, MockDrafter, fan_out
from .store import Store


def seed(store: Store) -> None:
    for name in ("professional", "social", "family", "formal"):
        store.upsert_register(Register(id=name, name=name, is_mature=(name != "family")))

    contacts = [
        Contact(id="alice", display_name="Alice", handles=["alice@investco.com"],
                tier=Tier.T1, register_id="professional"),
        Contact(id="sam", display_name="Sam", handles=["sam@co.com"],
                tier=Tier.T2, register_id="professional"),
        Contact(id="jordan", display_name="Jordan", handles=["+15551234567"],
                tier=Tier.T3, register_id="social"),
        Contact(id="pat", display_name="Pat", handles=["+15559876543"],
                tier=Tier.T3, register_id="social"),
        # Untiered AND already deferred 3x — demonstrates both the tier
        # prompt (§10 Q10) and deferral escalation (§5B.4) at once.
        Contact(id="morgan", display_name="Morgan", handles=["morgan@company.com"],
                tier=Tier.UNTIERED, deferral_count=3),
    ]
    for c in contacts:
        store.upsert_contact(c)

    # A fixed commitment (side-job shift) overlapping the Monday 2pm
    # conflict cluster below, so displacement has something to decide against.
    now = time.time()
    monday_2pm = _next_weekday_at(now, weekday=0, hour=14)
    store.upsert_calendar_event(CalendarEvent(
        id="shift", title="Side-job shift", start=monday_2pm - 3600, end=monday_2pm + 7200,
        commitment_class=CommitmentClass.FIXED,
    ))


def _next_weekday_at(reference_ts: float, weekday: int, hour: int) -> float:
    import datetime
    ref = datetime.datetime.fromtimestamp(reference_ts)
    days_ahead = (weekday - ref.weekday()) % 7 or 7
    target = (ref + datetime.timedelta(days=days_ahead)).replace(hour=hour, minute=0, second=0, microsecond=0)
    return target.timestamp()


def seed_messages(source: MockSource) -> None:
    source.add(RawMessage(handle="alice@investco.com", source=SourceType.GMAIL,
        body="Hi Ray, are you free Monday at 2pm to review the term sheet? Let me know."))
    source.add(RawMessage(handle="+15551234567", source=SourceType.SMS,
        body="hey are you free monday 2pm to hang out?"))
    source.add(RawMessage(handle="+15559876543", source=SourceType.SMS,
        body="yo you free monday 2pm for the game?"))
    source.add(RawMessage(handle="sam@co.com", source=SourceType.GMAIL,
        body="Are you coming to the offsite Friday? Let me know."))
    source.add(RawMessage(handle="morgan@company.com", source=SourceType.GMAIL,
        body="You in for the offsite Friday? Let me know."))
    source.add(RawMessage(handle="noreply@dealsnow.com", source=SourceType.GMAIL,
        body="Unsubscribe from our newsletter now!"))
    source.add(RawMessage(handle="billing@vendor.com", source=SourceType.GMAIL,
        body="FYI the invoice was paid."))


def _print_item(item: BriefingItem, index: int) -> None:
    names = ", ".join(c.display_name for c in item.contacts)
    kind = item.cluster.type.value if item.cluster else "single message"
    print(f"\n[{index}] ({kind}) — {names}"
          f"{'  ⚠ ESCALATED' if item.escalated else ''}"
          f"{'  • needs tier assignment' if item.needs_tier_prompt else ''}")
    for m in item.messages:
        print(f"    · {m.body!r}")


def _displacement_note(item: BriefingItem, store: Store) -> None:
    if not item.cluster or item.cluster.type != ClusterType.CALENDAR_CONFLICT:
        return
    slot = next((m.proposed_slot for m in item.messages if m.proposed_slot), None)
    if not slot:
        return
    conflicts = store.events_overlapping(*slot)
    if not conflicts:
        print("    (no calendar conflict — slot is open)")
        return
    event = conflicts[0]
    for contact in item.contacts:
        result = decide_displacement(contact.tier, event.commitment_class)
        print(f"    displacement vs {event.title!r} ({event.commitment_class.value}) "
              f"for {contact.display_name} ({contact.tier.value}): {result.recommendation.value} "
              f"— {result.rationale}")


def _print_fanout(result: FanOutResult) -> None:
    for d in result.drafts:
        print(f"    draft [{d.register_id}]: {d.body!r}")
    for a, b in result.near_duplicate_pairs:
        print(f"    ⚠ near-duplicate drafts: {a} / {b}")
    for did in result.register_mismatch_ids:
        print(f"    ⚠ register mismatch on draft {did}")


def run_demo(interactive: bool = False) -> None:
    store = Store(":memory:")
    seed(store)

    source = MockSource()
    seed_messages(source)

    print("=== Ingesting + normalizing + triaging ===")
    messages = [normalize(raw, store) for raw in source.fetch_new()]
    messages = [triage_message(m, store) for m in messages]
    for m in messages:
        print(f"  {m.classification.value:14s} urgency={m.urgency_score:6.1f}  {m.body!r}")

    print("\n=== Clustering ===")
    remaining = apply_prior_decisions(messages, store, now=time.time())
    clusters = cluster_messages(remaining, store)
    print(f"  {len(clusters)} cluster(s) formed")

    print("\n=== Briefing ===")
    briefing = build_briefing(store)
    for i, item in enumerate(briefing):
        _print_item(item, i)
        _displacement_note(item, store)

    print("\n=== Intent capture + voice engine + review ===")
    drafter = MockDrafter()
    for i, item in enumerate(briefing):
        for contact in item.contacts:
            if contact.tier == Tier.UNTIERED:
                if interactive:
                    tier_in = input(f"    Assign a tier to {contact.display_name} (T1-T4): ").strip()
                    contact.tier = Tier(tier_in) if tier_in in Tier.__members__ else Tier.T3
                else:
                    contact.tier = Tier.T3  # scripted default for the walkthrough
                store.upsert_contact(contact)

        if interactive:
            intent = input(f"    [{i}] Your answer for {', '.join(c.display_name for c in item.contacts)}: ")
        else:
            intent = "Sorry, I'm booked then — can we do Tuesday same time instead?" \
                if (item.cluster and item.cluster.type == ClusterType.CALENDAR_CONFLICT) \
                else "Yes, count me in — thanks for checking!"
        if not intent.strip():
            print(f"    [{i}] deferred")
            defer(item, store)
            continue

        decision = Decision(intent_text=intent, scope={
            "slot": list(next((m.proposed_slot for m in item.messages if m.proposed_slot), (0, 0)))
        })
        store.upsert_decision(decision)
        if item.cluster:
            attach_decision(item.cluster, decision, store)

        result = fan_out(decision, item.messages, store, drafter)
        _print_fanout(result)

        for d in result.drafts:
            send(d, store)
        resolve(item, store)
        print(f"    [{i}] sent {len(result.drafts)} draft(s)")

    print("\n=== Demonstrating intent reuse (§5A.4) ===")
    source.add(RawMessage(handle="+15551111111", source=SourceType.SMS,
        body="hey are you around monday 2pm too?"))
    late_messages = [normalize(raw, store) for raw in source.fetch_new()]
    late_messages = [triage_message(m, store) for m in late_messages]
    absorbed_remaining = apply_prior_decisions(late_messages, store, now=time.time())
    if len(absorbed_remaining) < len(late_messages):
        print("  late message joined an existing Decision instead of starting fresh clustering.")
    else:
        print("  no active Decision covered that slot — it would enter fresh clustering.")

    store.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interactive", action="store_true",
                         help="prompt for real tier assignments and intents instead of scripted answers")
    args = parser.parse_args()
    run_demo(interactive=args.interactive)


if __name__ == "__main__":
    main()
