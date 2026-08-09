import pytest

from assistant.models import CommitmentClass, Tier
from assistant.pipeline.displacement import Recommendation, decide_displacement


@pytest.mark.parametrize("tier", [Tier.T1, Tier.T2, Tier.T3, Tier.T4, Tier.UNTIERED])
def test_fixed_never_displaces(tier):
    assert decide_displacement(tier, CommitmentClass.FIXED).recommendation == Recommendation.DECLINE


def test_group_locked_only_moves_for_t1():
    assert decide_displacement(Tier.T1, CommitmentClass.GROUP_LOCKED).recommendation == Recommendation.PROPOSE_RESCHEDULE
    for tier in (Tier.T2, Tier.T3, Tier.T4, Tier.UNTIERED):
        assert decide_displacement(tier, CommitmentClass.GROUP_LOCKED).recommendation == Recommendation.DECLINE


def test_flexible_moves_for_t1_t2_t3_only():
    for tier in (Tier.T1, Tier.T2, Tier.T3):
        assert decide_displacement(tier, CommitmentClass.FLEXIBLE).recommendation == Recommendation.PROPOSE_RESCHEDULE
    for tier in (Tier.T4, Tier.UNTIERED):
        assert decide_displacement(tier, CommitmentClass.FLEXIBLE).recommendation == Recommendation.DECLINE


@pytest.mark.parametrize("tier", [Tier.T1, Tier.T2, Tier.T3, Tier.T4, Tier.UNTIERED])
def test_soft_always_proposes_reschedule(tier):
    assert decide_displacement(tier, CommitmentClass.SOFT).recommendation == Recommendation.PROPOSE_RESCHEDULE


def test_untiered_treated_as_t4():
    untiered = decide_displacement(Tier.UNTIERED, CommitmentClass.FLEXIBLE)
    t4 = decide_displacement(Tier.T4, CommitmentClass.FLEXIBLE)
    assert untiered.recommendation == t4.recommendation
