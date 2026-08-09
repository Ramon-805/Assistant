# Personal Message Assistant

Design doc: [`BLUEPRINT.md`](./BLUEPRINT.md). This repo is an early scaffold
of the architecture described there — a runnable skeleton of the
pipeline and persistent state store, not a finished product.

## What's here

`assistant/models.py` and `assistant/store.py` implement the data model and
persistent state store from blueprint §4.2/§4.3 (SQLite-backed, zero external
dependencies). `assistant/pipeline/` implements each pipeline stage from §4.1
as a real, tested module:

| Module | Blueprint section | Status |
|---|---|---|
| `ingestion.py` | §7 | Interface + `MockSource` only — see "What's stubbed" |
| `normalization.py` | §4.1 | Working — handle-to-Contact resolution |
| `triage.py` | §5 | Working heuristics (keyword classification, regex date extraction) |
| `clustering.py` | §5A | Working for `calendar_conflict` / `same_question`; `same_decision` is an open TODO |
| `displacement.py` | §5B | Working — full displacement rule table |
| `briefing.py` | §5B.4, §10 Q10 | Working — deferral escalation + tier-prompt flagging |
| `voice.py` | §6 | Interface (`Drafter`) + `MockDrafter` only — see below |
| `dispatch.py` | §4.1 write-backs, §6.4 | Working — defer/resolve/edit write-backs to Contact and Register |

`assistant/cli.py` wires all of this into one runnable, scripted walkthrough —
the Phase 2 "manual run-my-brief button" the blueprint calls for, over seed
data instead of a real inbox.

## What's stubbed, and why

Two things this scaffold cannot do without credentials and access this
environment doesn't have:

- **Real ingestion** (`GmailSource`, `OutlookSource`, `SmsSource`,
  `NotificationSource` in `ingestion.py`) — each needs OAuth or, for SMS/
  notifications, an actual Android runtime. They raise `NotImplementedError`
  with a `TODO` pointing at what real integration looks like, rather than
  faking a response.
- **Real drafting** (`voice.py`) — `MockDrafter` fills fixed templates per
  register so the fan-out, near-duplicate, and register-mismatch logic
  around it is exercisable and tested. It is not an LLM and does not draw on
  your actual writing. Per the blueprint's own Phase 1 gate (§9), *proving
  drafts are convincingly your voice is supposed to happen before anything
  else is built* — this scaffold intentionally does not skip that gate by
  faking it. A real `Drafter` needs a corpus of your sent messages (§6.1)
  and a call to a frontier model, plus the blind A/B test in §6.3.

Everything else — clustering, displacement, deferral escalation, the
persistent state store, the write-back edges — is real, working code you
can read, run, and extend.

## Running it

```bash
pip install -r requirements.txt

# scripted walkthrough over seed data — no input required
python3 -m assistant.cli

# same, but prompts you for tier assignments and intents
python3 -m assistant.cli --interactive

pytest
```

The demo seeds a handful of contacts and messages that exercise a calendar-
conflict cluster (with a displacement recommendation against a fixed
commitment), a same-question cluster, an escalated/untiered contact, noise/
FYI filtering, and intent reuse across a simulated second briefing.

## Next steps, per the blueprint's own phased plan (§9)

1. **Prove the voice engine (Phase 1)** — replace `MockDrafter` with a real
   LLM-backed `Drafter`, trained/prompted against an actual corpus of sent
   messages partitioned into at least the Professional and Social registers,
   and run the blind A/B test. This is the gate everything else depends on.
2. **Wire up Gmail** (`GmailSource`) for the Phase 2 vertical slice — read +
   send, real OAuth.
3. Everything downstream (calendar, clustering polish, multi-channel, the
   learning loop) has a home in the existing module layout already.
