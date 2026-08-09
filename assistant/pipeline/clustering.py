"""Clustering engine — §5A.

Groups messages by the decision they require. Deliberately biased
toward under-clustering (§5A.3): thresholds are conservative, and a
contact flagged always_individual is never clustered at all.

same_decision clustering (§5A.1) needs real semantic understanding —
"three requests that all depend on whether I'm traveling that week"
— which is out of reach of the keyword/overlap heuristics used here.
It's left as an explicit TODO rather than faked with a heuristic that
would silently over-cluster, which the blueprint calls the worse
failure mode.
"""

from __future__ import annotations

from itertools import combinations

from ..models import Classification, Cluster, ClusterType, Decision, Message
from ..store import Store

SAME_QUESTION_JACCARD_THRESHOLD = 0.5


def _overlaps(a: tuple[float, float], b: tuple[float, float]) -> bool:
    return a[0] < b[1] and b[0] < a[1]


def _jaccard(a: str, b: str) -> float:
    words_a, words_b = set(a.lower().split()), set(b.lower().split())
    if not words_a or not words_b:
        return 0.0
    return len(words_a & words_b) / len(words_a | words_b)


def apply_prior_decisions(messages: list[Message], store: Store, now: float) -> list[Message]:
    """§5A.4 — a message whose proposed slot falls inside an unexpired
    Decision's scope joins that decision instead of entering fresh
    clustering. Returns the messages that were NOT absorbed this way."""
    remaining = []
    active = store.list_active_decisions(now)
    for message in messages:
        absorbed = False
        if message.classification == Classification.NEEDS_CALENDAR and message.proposed_slot:
            for decision in active:
                slot = decision.scope.get("slot")
                if slot and _overlaps(tuple(slot), message.proposed_slot):
                    message.cluster_id = None  # no new cluster; decision reused directly
                    cluster = Cluster(
                        type=ClusterType.CALENDAR_CONFLICT,
                        message_ids=[message.id],
                        decision_id=decision.id,
                    )
                    store.upsert_cluster(cluster)
                    message.cluster_id = cluster.id
                    store.upsert_message(message)
                    absorbed = True
                    break
        if not absorbed:
            remaining.append(message)
    return remaining


def cluster_messages(messages: list[Message], store: Store) -> list[Cluster]:
    """Only NEEDS_REPLY / NEEDS_CALENDAR messages enter the briefing
    queue (§5) and are eligible for clustering. always_individual
    contacts are excluded per §5A.3."""
    eligible = [
        m for m in messages
        if m.classification in (Classification.NEEDS_REPLY, Classification.NEEDS_CALENDAR)
    ]
    individual_ids = {
        c.id for c in store.list_contacts() if c.always_individual
    }
    eligible = [m for m in eligible if m.contact_id not in individual_ids]

    clusters: list[Cluster] = []
    clustered: set[str] = set()

    # Calendar-conflict clusters: overlapping proposed slots.
    calendar_msgs = [m for m in eligible if m.classification == Classification.NEEDS_CALENDAR
                      and m.proposed_slot and m.id not in clustered]
    for a, b in combinations(calendar_msgs, 2):
        if a.id in clustered or b.id in clustered:
            continue
        if _overlaps(a.proposed_slot, b.proposed_slot):
            group = [m for m in calendar_msgs if m.id not in clustered
                     and _overlaps(m.proposed_slot, a.proposed_slot)]
            cluster = Cluster(type=ClusterType.CALENDAR_CONFLICT, message_ids=[m.id for m in group])
            store.upsert_cluster(cluster)
            for m in group:
                m.cluster_id = cluster.id
                store.upsert_message(m)
                clustered.add(m.id)
            clusters.append(cluster)

    # Same-question clusters: high text-similarity NEEDS_REPLY messages.
    reply_msgs = [m for m in eligible if m.classification == Classification.NEEDS_REPLY
                  and m.id not in clustered]
    for a, b in combinations(reply_msgs, 2):
        if a.id in clustered or b.id in clustered:
            continue
        if _jaccard(a.body, b.body) >= SAME_QUESTION_JACCARD_THRESHOLD:
            group = [m for m in reply_msgs if m.id not in clustered
                     and _jaccard(m.body, a.body) >= SAME_QUESTION_JACCARD_THRESHOLD]
            cluster = Cluster(type=ClusterType.SAME_QUESTION, message_ids=[m.id for m in group])
            store.upsert_cluster(cluster)
            for m in group:
                m.cluster_id = cluster.id
                store.upsert_message(m)
                clustered.add(m.id)
            clusters.append(cluster)

    # same_decision clustering: TODO — needs semantic grouping beyond
    # what keyword/overlap heuristics can safely do. Left unclustered
    # (under-cluster bias) rather than guessed at.

    return clusters


def attach_decision(cluster: Cluster, decision: Decision, store: Store) -> None:
    cluster.decision_id = decision.id
    store.upsert_cluster(cluster)
