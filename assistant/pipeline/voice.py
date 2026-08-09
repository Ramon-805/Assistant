"""Voice engine — §6.

The differentiating component, per the blueprint — and the one this
scaffold can least fake convincingly. Drafter is the pluggable seam:
MockDrafter below is template-based so the pipeline is runnable and
testable with zero external dependencies. A real Drafter backed by a
frontier cloud model, trained on the user's actual sent-message corpus
per register, is Phase 1's whole job (§9) — it doesn't exist yet.

fan_out implements the two safety nets the blueprint treats as
non-negotiable:
  - near-duplicate check across a cluster's drafts (§5A.2)
  - register-mismatch detection (§6.2.5)
Both are heuristic here (word overlap / keyword markers) and would
need to be replaced by something more robust before real use.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from itertools import combinations

from ..models import (
    Contact,
    Decision,
    Draft,
    FALLBACK_REGISTER,
    GeneratedBy,
    Message,
    Register,
)
from ..store import Store

NEAR_DUPLICATE_JACCARD_THRESHOLD = 0.85

_SLANG_MARKERS = {"bro", "man", "lol", "yo", "gonna", "wanna", "haha"}
_FORMAL_MARKERS = {"regards", "sincerely", "dear"}


class Drafter(ABC):
    @abstractmethod
    def generate(
        self,
        intent: str,
        contact: Contact,
        register: Register,
        modifier: str,
        thread_history: list[Message],
    ) -> str:
        ...


class MockDrafter(Drafter):
    """Deterministic templates — a stand-in for a real LLM call.
    Good enough to exercise fan-out, near-duplicate, and mismatch
    logic; not good enough to pass the Phase 1 voice-match gate."""

    _TEMPLATES = {
        "professional": "Hi {name},\n\n{intent}\n\nBest,\nRay",
        "social": "hey {name} — {intent_lower}",
        "family": "Hey {name}, {intent}. Love you!",
        "formal": "Dear {name},\n\n{intent}\n\nRegards,\nRay",
    }

    _MODIFIER_PREFIX = {
        "apologetic": "Sorry about this — ",
        "declining": "",
        "celebratory": "",
        "bad_news": "",
        "urgent": "Quick one — ",
        "routine": "",
    }

    def generate(self, intent, contact, register, modifier, thread_history) -> str:
        template = self._TEMPLATES.get(register.name, self._TEMPLATES[FALLBACK_REGISTER])
        prefix = self._MODIFIER_PREFIX.get(modifier, "")
        filled_intent = f"{prefix}{intent}"
        return template.format(
            name=contact.display_name or "there",
            intent=filled_intent,
            intent_lower=filled_intent[:1].lower() + filled_intent[1:] if filled_intent else "",
        )


def _jaccard(a: str, b: str) -> float:
    words_a, words_b = set(a.lower().split()), set(b.lower().split())
    if not words_a or not words_b:
        return 0.0
    return len(words_a & words_b) / len(words_a | words_b)


def _register_mismatch(body: str, register: Register) -> bool:
    words = set(body.lower().replace(",", "").replace(".", "").split())
    if register.name in ("professional", "formal"):
        return bool(words & _SLANG_MARKERS)
    if register.name == "social":
        return bool(words & _FORMAL_MARKERS)
    return False


@dataclass
class FanOutResult:
    drafts: list[Draft] = field(default_factory=list)
    near_duplicate_pairs: list[tuple[str, str]] = field(default_factory=list)
    register_mismatch_ids: list[str] = field(default_factory=list)


def fan_out(
    decision: Decision,
    messages: list[Message],
    store: Store,
    drafter: Drafter,
    modifier: str = "routine",
) -> FanOutResult:
    """§5A.2 — one intent, N independently-generated drafts. Never one
    body reused across recipients."""
    result = FanOutResult()

    for message in messages:
        contact = store.get_contact(message.contact_id)
        if contact is None:
            continue

        register = store.get_register(contact.register_id) if contact.register_id else None
        if register is None:
            # §6.2.5 — uncertain register fails toward formality, not casualness.
            register = store.get_register(FALLBACK_REGISTER) or Register(
                id=FALLBACK_REGISTER, name=FALLBACK_REGISTER, is_mature=True
            )

        thread_history = store.thread_history(message.thread_id) if message.thread_id else []
        body = drafter.generate(decision.intent_text, contact, register, modifier, thread_history)

        draft = Draft(
            message_id=message.id,
            decision_id=decision.id,
            register_id=register.id,
            modifier=modifier,
            generated_by=GeneratedBy.CLOUD,  # routing policy is an open question, §11.5
            confidence=1.0 if register.is_mature else 0.5,
            body=body,
        )
        store.upsert_draft(draft)
        result.drafts.append(draft)

        if _register_mismatch(body, register):
            result.register_mismatch_ids.append(draft.id)

    # Near-duplicate check: only meaningful within the same register —
    # cross-register drafts are expected to differ already (§6.2.4).
    for a, b in combinations(result.drafts, 2):
        if a.register_id != b.register_id:
            continue
        if _jaccard(a.body, b.body) >= NEAR_DUPLICATE_JACCARD_THRESHOLD:
            result.near_duplicate_pairs.append((a.id, b.id))

    return result
