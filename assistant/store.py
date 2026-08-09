"""Persistent state store — §4.1/§4.3.

Everything the pipeline reads from and writes back to. The pipeline
itself is stateless per-run; this module is the durable layer.

SQLite is used as the storage engine so the store runs with zero
external dependencies. The schema is deliberately simple (one table
per entity, JSON for list/dict fields) since the goal here is a
correct, inspectable scaffold rather than a production data layer.
"""

from __future__ import annotations

import json
import sqlite3
from typing import Optional

from .models import (
    CalendarEvent,
    Cluster,
    ClusterType,
    Contact,
    Decision,
    Draft,
    DraftStatus,
    GeneratedBy,
    Message,
    Register,
    Classification,
    CommitmentClass,
    SourceType,
    Tier,
)

SCHEMA = """
CREATE TABLE IF NOT EXISTS contacts (
    id TEXT PRIMARY KEY,
    display_name TEXT,
    handles TEXT,
    tier TEXT,
    register_id TEXT,
    always_individual INTEGER,
    deferral_count INTEGER,
    last_replied_at REAL,
    reply_latency_avg REAL,
    local_only INTEGER
);

CREATE TABLE IF NOT EXISTS registers (
    id TEXT PRIMARY KEY,
    name TEXT,
    assignment_rule TEXT,
    sample_count INTEGER,
    is_mature INTEGER
);

CREATE TABLE IF NOT EXISTS calendar_events (
    id TEXT PRIMARY KEY,
    title TEXT,
    start REAL,
    end REAL,
    commitment_class TEXT
);

CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    contact_id TEXT,
    source TEXT,
    source_app TEXT,
    body TEXT,
    received_at REAL,
    thread_id TEXT,
    is_truncated INTEGER,
    can_reply_direct INTEGER,
    classification TEXT,
    urgency_score REAL,
    cluster_id TEXT,
    proposed_slot TEXT
);

CREATE TABLE IF NOT EXISTS clusters (
    id TEXT PRIMARY KEY,
    type TEXT,
    message_ids TEXT,
    decision_id TEXT,
    proposed_at REAL
);

CREATE TABLE IF NOT EXISTS decisions (
    id TEXT PRIMARY KEY,
    intent_text TEXT,
    resolved_at REAL,
    scope TEXT,
    expires_at REAL
);

CREATE TABLE IF NOT EXISTS drafts (
    id TEXT PRIMARY KEY,
    message_id TEXT,
    decision_id TEXT,
    register_id TEXT,
    modifier TEXT,
    generated_by TEXT,
    confidence REAL,
    body TEXT,
    status TEXT
);
"""


class Store:
    """Thin, explicit CRUD layer. No ORM — the schema is small enough
    that hand-written SQL stays more legible than a mapping layer."""

    def __init__(self, path: str = ":memory:"):
        self._conn = sqlite3.connect(path)
        self._conn.row_factory = sqlite3.Row
        with self._conn:
            self._conn.executescript(SCHEMA)

    def close(self) -> None:
        self._conn.close()

    # ---- Contacts -------------------------------------------------

    def upsert_contact(self, c: Contact) -> None:
        with self._conn:
            self._conn.execute(
                """INSERT INTO contacts
                   (id, display_name, handles, tier, register_id, always_individual,
                    deferral_count, last_replied_at, reply_latency_avg, local_only)
                   VALUES (?,?,?,?,?,?,?,?,?,?)
                   ON CONFLICT(id) DO UPDATE SET
                     display_name=excluded.display_name, handles=excluded.handles,
                     tier=excluded.tier, register_id=excluded.register_id,
                     always_individual=excluded.always_individual,
                     deferral_count=excluded.deferral_count,
                     last_replied_at=excluded.last_replied_at,
                     reply_latency_avg=excluded.reply_latency_avg,
                     local_only=excluded.local_only""",
                (
                    c.id, c.display_name, json.dumps(c.handles), c.tier.value,
                    c.register_id, int(c.always_individual), c.deferral_count,
                    c.last_replied_at, c.reply_latency_avg, int(c.local_only),
                ),
            )

    def get_contact(self, contact_id: str) -> Optional[Contact]:
        row = self._conn.execute("SELECT * FROM contacts WHERE id=?", (contact_id,)).fetchone()
        return _row_to_contact(row) if row else None

    def find_contact_by_handle(self, handle: str) -> Optional[Contact]:
        """Handle-to-Contact resolution — §4.2. Linear scan is fine at
        scaffold scale; a real deployment would index handles separately."""
        for row in self._conn.execute("SELECT * FROM contacts"):
            handles = json.loads(row["handles"])
            if handle in handles:
                return _row_to_contact(row)
        return None

    def list_untiered_contacts(self) -> list[Contact]:
        rows = self._conn.execute("SELECT * FROM contacts WHERE tier=?", (Tier.UNTIERED.value,))
        return [_row_to_contact(r) for r in rows]

    def list_contacts(self) -> list[Contact]:
        return [_row_to_contact(r) for r in self._conn.execute("SELECT * FROM contacts")]

    # ---- Registers --------------------------------------------------

    def upsert_register(self, r: Register) -> None:
        with self._conn:
            self._conn.execute(
                """INSERT INTO registers (id, name, assignment_rule, sample_count, is_mature)
                   VALUES (?,?,?,?,?)
                   ON CONFLICT(id) DO UPDATE SET
                     name=excluded.name, assignment_rule=excluded.assignment_rule,
                     sample_count=excluded.sample_count, is_mature=excluded.is_mature""",
                (r.id, r.name, r.assignment_rule, r.sample_count, int(r.is_mature)),
            )

    def get_register(self, register_id: str) -> Optional[Register]:
        row = self._conn.execute("SELECT * FROM registers WHERE id=?", (register_id,)).fetchone()
        if not row:
            return None
        return Register(
            id=row["id"], name=row["name"], assignment_rule=row["assignment_rule"],
            sample_count=row["sample_count"], is_mature=bool(row["is_mature"]),
        )

    # ---- Calendar ---------------------------------------------------

    def upsert_calendar_event(self, e: CalendarEvent) -> None:
        with self._conn:
            self._conn.execute(
                """INSERT INTO calendar_events (id, title, start, end, commitment_class)
                   VALUES (?,?,?,?,?)
                   ON CONFLICT(id) DO UPDATE SET
                     title=excluded.title, start=excluded.start, end=excluded.end,
                     commitment_class=excluded.commitment_class""",
                (e.id, e.title, e.start, e.end, e.commitment_class.value),
            )

    def events_overlapping(self, start: float, end: float) -> list[CalendarEvent]:
        rows = self._conn.execute(
            "SELECT * FROM calendar_events WHERE start < ? AND end > ?", (end, start)
        )
        return [
            CalendarEvent(
                id=r["id"], title=r["title"], start=r["start"], end=r["end"],
                commitment_class=CommitmentClass(r["commitment_class"]),
            )
            for r in rows
        ]

    # ---- Messages -----------------------------------------------------

    def upsert_message(self, m: Message) -> None:
        with self._conn:
            self._conn.execute(
                """INSERT INTO messages
                   (id, contact_id, source, source_app, body, received_at, thread_id,
                    is_truncated, can_reply_direct, classification, urgency_score,
                    cluster_id, proposed_slot)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                   ON CONFLICT(id) DO UPDATE SET
                     contact_id=excluded.contact_id, source=excluded.source,
                     source_app=excluded.source_app, body=excluded.body,
                     received_at=excluded.received_at, thread_id=excluded.thread_id,
                     is_truncated=excluded.is_truncated, can_reply_direct=excluded.can_reply_direct,
                     classification=excluded.classification, urgency_score=excluded.urgency_score,
                     cluster_id=excluded.cluster_id, proposed_slot=excluded.proposed_slot""",
                (
                    m.id, m.contact_id, m.source.value, m.source_app, m.body, m.received_at,
                    m.thread_id, int(m.is_truncated), int(m.can_reply_direct),
                    m.classification.value if m.classification else None, m.urgency_score,
                    m.cluster_id, json.dumps(m.proposed_slot) if m.proposed_slot else None,
                ),
            )

    def get_message(self, message_id: str) -> Optional[Message]:
        row = self._conn.execute("SELECT * FROM messages WHERE id=?", (message_id,)).fetchone()
        return _row_to_message(row) if row else None

    def list_messages(self, classification: Optional[Classification] = None) -> list[Message]:
        if classification:
            rows = self._conn.execute(
                "SELECT * FROM messages WHERE classification=?", (classification.value,)
            )
        else:
            rows = self._conn.execute("SELECT * FROM messages")
        return [_row_to_message(r) for r in rows]

    def thread_history(self, thread_id: str, limit: int = 10) -> list[Message]:
        """Rolling window per §4.4 retention policy."""
        rows = self._conn.execute(
            "SELECT * FROM messages WHERE thread_id=? ORDER BY received_at DESC LIMIT ?",
            (thread_id, limit),
        )
        return [_row_to_message(r) for r in rows]

    # ---- Clusters -----------------------------------------------------

    def upsert_cluster(self, c: Cluster) -> None:
        with self._conn:
            self._conn.execute(
                """INSERT INTO clusters (id, type, message_ids, decision_id, proposed_at)
                   VALUES (?,?,?,?,?)
                   ON CONFLICT(id) DO UPDATE SET
                     type=excluded.type, message_ids=excluded.message_ids,
                     decision_id=excluded.decision_id, proposed_at=excluded.proposed_at""",
                (c.id, c.type.value, json.dumps(c.message_ids), c.decision_id, c.proposed_at),
            )

    def list_clusters(self) -> list[Cluster]:
        rows = self._conn.execute("SELECT * FROM clusters")
        return [_row_to_cluster(r) for r in rows]

    # ---- Decisions ------------------------------------------------------

    def upsert_decision(self, d: Decision) -> None:
        with self._conn:
            self._conn.execute(
                """INSERT INTO decisions (id, intent_text, resolved_at, scope, expires_at)
                   VALUES (?,?,?,?,?)
                   ON CONFLICT(id) DO UPDATE SET
                     intent_text=excluded.intent_text, resolved_at=excluded.resolved_at,
                     scope=excluded.scope, expires_at=excluded.expires_at""",
                (d.id, d.intent_text, d.resolved_at, json.dumps(d.scope), d.expires_at),
            )

    def list_active_decisions(self, now: float) -> list[Decision]:
        rows = self._conn.execute(
            "SELECT * FROM decisions WHERE expires_at IS NULL OR expires_at > ?", (now,)
        )
        return [_row_to_decision(r) for r in rows]

    def get_decision(self, decision_id: str) -> Optional[Decision]:
        row = self._conn.execute("SELECT * FROM decisions WHERE id=?", (decision_id,)).fetchone()
        return _row_to_decision(row) if row else None

    # ---- Drafts -----------------------------------------------------------

    def upsert_draft(self, d: Draft) -> None:
        with self._conn:
            self._conn.execute(
                """INSERT INTO drafts
                   (id, message_id, decision_id, register_id, modifier, generated_by,
                    confidence, body, status)
                   VALUES (?,?,?,?,?,?,?,?,?)
                   ON CONFLICT(id) DO UPDATE SET
                     message_id=excluded.message_id, decision_id=excluded.decision_id,
                     register_id=excluded.register_id, modifier=excluded.modifier,
                     generated_by=excluded.generated_by, confidence=excluded.confidence,
                     body=excluded.body, status=excluded.status""",
                (
                    d.id, d.message_id, d.decision_id, d.register_id, d.modifier,
                    d.generated_by.value, d.confidence, d.body, d.status.value,
                ),
            )

    def list_drafts_for_decision(self, decision_id: str) -> list[Draft]:
        rows = self._conn.execute("SELECT * FROM drafts WHERE decision_id=?", (decision_id,))
        return [_row_to_draft(r) for r in rows]


# ---- row -> dataclass helpers --------------------------------------------

def _row_to_contact(row: sqlite3.Row) -> Contact:
    return Contact(
        id=row["id"], display_name=row["display_name"], handles=json.loads(row["handles"]),
        tier=Tier(row["tier"]), register_id=row["register_id"],
        always_individual=bool(row["always_individual"]), deferral_count=row["deferral_count"],
        last_replied_at=row["last_replied_at"], reply_latency_avg=row["reply_latency_avg"],
        local_only=bool(row["local_only"]),
    )


def _row_to_message(row: sqlite3.Row) -> Message:
    return Message(
        id=row["id"], contact_id=row["contact_id"], source=SourceType(row["source"]),
        source_app=row["source_app"], body=row["body"], received_at=row["received_at"],
        thread_id=row["thread_id"], is_truncated=bool(row["is_truncated"]),
        can_reply_direct=bool(row["can_reply_direct"]),
        classification=Classification(row["classification"]) if row["classification"] else None,
        urgency_score=row["urgency_score"], cluster_id=row["cluster_id"],
        proposed_slot=tuple(json.loads(row["proposed_slot"])) if row["proposed_slot"] else None,
    )


def _row_to_cluster(row: sqlite3.Row) -> Cluster:
    return Cluster(
        id=row["id"], type=ClusterType(row["type"]), message_ids=json.loads(row["message_ids"]),
        decision_id=row["decision_id"], proposed_at=row["proposed_at"],
    )


def _row_to_decision(row: sqlite3.Row) -> Decision:
    return Decision(
        id=row["id"], intent_text=row["intent_text"], resolved_at=row["resolved_at"],
        scope=json.loads(row["scope"]), expires_at=row["expires_at"],
    )


def _row_to_draft(row: sqlite3.Row) -> Draft:
    return Draft(
        id=row["id"], message_id=row["message_id"], decision_id=row["decision_id"],
        register_id=row["register_id"], modifier=row["modifier"],
        generated_by=GeneratedBy(row["generated_by"]), confidence=row["confidence"],
        body=row["body"], status=DraftStatus(row["status"]),
    )
