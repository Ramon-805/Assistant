"""Priority & Displacement Model — §5B.

Two independent axes (who's asking, what's already booked) combine
into a recommendation. This never changes the calendar itself — the
caller surfaces the recommendation in the briefing for confirmation.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from ..models import CommitmentClass, Tier

# UNTIERED is treated as T4 (displaces nothing) until the contact is
# assigned a real tier — §5B.2.
_EFFECTIVE_TIER = {
    Tier.T1: Tier.T1,
    Tier.T2: Tier.T2,
    Tier.T3: Tier.T3,
    Tier.T4: Tier.T4,
    Tier.UNTIERED: Tier.T4,
}


class Recommendation(str, Enum):
    DECLINE = "decline"
    PROPOSE_RESCHEDULE = "propose_reschedule"


@dataclass
class DisplacementResult:
    recommendation: Recommendation
    rationale: str


def decide_displacement(tier: Tier, commitment_class: CommitmentClass) -> DisplacementResult:
    effective = _EFFECTIVE_TIER[tier]

    if commitment_class == CommitmentClass.FIXED:
        return DisplacementResult(Recommendation.DECLINE, "Fixed commitments never move.")

    if commitment_class == CommitmentClass.GROUP_LOCKED:
        if effective == Tier.T1:
            return DisplacementResult(
                Recommendation.PROPOSE_RESCHEDULE, "T1 request against a group-locked commitment."
            )
        return DisplacementResult(
            Recommendation.DECLINE, "Group-locked commitments only move for T1 requests."
        )

    if commitment_class == CommitmentClass.FLEXIBLE:
        if effective in (Tier.T1, Tier.T2, Tier.T3):
            return DisplacementResult(
                Recommendation.PROPOSE_RESCHEDULE, f"{effective.value} request against a flexible commitment."
            )
        return DisplacementResult(Recommendation.DECLINE, "T4/UNTIERED requests don't displace anything.")

    if commitment_class == CommitmentClass.SOFT:
        return DisplacementResult(
            Recommendation.PROPOSE_RESCHEDULE, "Soft/tentative commitments move for any tier."
        )

    raise ValueError(f"unhandled commitment class {commitment_class!r}")
