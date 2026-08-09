"""Data model — mirrors BLUEPRINT.md §4.2.

All durable behavior lives on Contact. Message/Cluster/Decision/Draft
are the per-run pipeline entities that reference it.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


def new_id() -> str:
    return uuid.uuid4().hex[:12]


def now() -> float:
    return time.time()


class Tier(str, Enum):
    T1 = "T1"
    T2 = "T2"
    T3 = "T3"
    T4 = "T4"
    UNTIERED = "UNTIERED"


class CommitmentClass(str, Enum):
    FIXED = "fixed"
    GROUP_LOCKED = "group_locked"
    FLEXIBLE = "flexible"
    SOFT = "soft"


class SourceType(str, Enum):
    GMAIL = "gmail"
    OUTLOOK = "outlook"
    SMS = "sms"
    NOTIFICATION = "notification"


class Classification(str, Enum):
    NEEDS_REPLY = "needs_reply"
    NEEDS_CALENDAR = "needs_calendar"
    FYI = "fyi"
    NOISE = "noise"


class ClusterType(str, Enum):
    CALENDAR_CONFLICT = "calendar_conflict"
    SAME_QUESTION = "same_question"
    SAME_DECISION = "same_decision"


class DraftStatus(str, Enum):
    PENDING = "pending"
    EDITED = "edited"
    SENT = "sent"
    DISMISSED = "dismissed"


class GeneratedBy(str, Enum):
    ON_DEVICE = "on_device"
    CLOUD = "cloud"


# Default registers shipped in v1 (§6.2 — user-extensible, this is just the seed set).
DEFAULT_REGISTERS = ("professional", "social", "family", "formal")
FALLBACK_REGISTER = "formal"  # §6.2.5 — fail toward formality


@dataclass
class Contact:
    id: str = field(default_factory=new_id)
    display_name: str = ""
    handles: list[str] = field(default_factory=list)
    tier: Tier = Tier.UNTIERED
    register_id: Optional[str] = None  # None → falls back to FALLBACK_REGISTER
    always_individual: bool = False
    deferral_count: int = 0
    last_replied_at: Optional[float] = None
    reply_latency_avg: Optional[float] = None
    local_only: bool = False  # §10.1D — per-contact privacy hard-cap


@dataclass
class Register:
    id: str
    name: str
    assignment_rule: str = ""  # free-text description; contacts point at register_id directly
    sample_count: int = 0
    is_mature: bool = False  # gates low-confidence flagging, §6.2.2


@dataclass
class CalendarEvent:
    id: str = field(default_factory=new_id)
    title: str = ""
    start: float = 0.0
    end: float = 0.0
    commitment_class: CommitmentClass = CommitmentClass.FIXED  # unclassified → Fixed, §5B.2


@dataclass
class Message:
    id: str = field(default_factory=new_id)
    contact_id: str = ""
    source: SourceType = SourceType.GMAIL
    source_app: Optional[str] = None
    body: str = ""
    received_at: float = field(default_factory=now)
    thread_id: Optional[str] = None
    is_truncated: bool = False
    can_reply_direct: bool = True
    classification: Optional[Classification] = None
    urgency_score: float = 0.0
    cluster_id: Optional[str] = None
    proposed_slot: Optional[tuple[float, float]] = None  # extracted calendar intent, if any


@dataclass
class Cluster:
    id: str = field(default_factory=new_id)
    type: ClusterType = ClusterType.SAME_QUESTION
    message_ids: list[str] = field(default_factory=list)
    decision_id: Optional[str] = None
    proposed_at: float = field(default_factory=now)


@dataclass
class Decision:
    id: str = field(default_factory=new_id)
    intent_text: str = ""
    resolved_at: float = field(default_factory=now)
    scope: dict = field(default_factory=dict)
    expires_at: Optional[float] = None  # open question §11.7 — None means no auto-expiry yet


@dataclass
class Draft:
    id: str = field(default_factory=new_id)
    message_id: str = ""
    decision_id: str = ""
    register_id: str = FALLBACK_REGISTER
    modifier: str = "routine"
    generated_by: GeneratedBy = GeneratedBy.CLOUD
    confidence: float = 1.0
    body: str = ""
    status: DraftStatus = DraftStatus.PENDING
