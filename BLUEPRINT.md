# Personal Message Assistant — Blueprint v1

**Working name:** TBD
**Owner:** Ray
**Doc purpose:** Scope, architecture, and phased build plan for an AI "chief of staff" that consolidates incoming messages, prompts for intent, and ghostwrites replies in the user's voice.

---

## 1. Problem Statement

The user reliably composes replies mentally but fails to execute the send. The failure is not comprehension or intent — it is the friction between deciding what to say and typing it out across fragmented inboxes.

**Design implication:** The system's job is not to decide *what* to say. It is to (a) put every pending message in one place, (b) capture intent in the smallest possible input, and (c) do the typing.

---

## 2. Core Philosophy

**"One Decision, Many Replies."**

The unit of work is not the message. It is the *decision*. Multiple messages frequently resolve to a single decision — three people proposing Monday 2pm all get the same answer, because the answer is about the user's calendar, not about the sender.

- **One Inbox** — every message needing a response, regardless of source, in a single queue.
- **One Decision** — messages are clustered by the decision they require. The assistant asks once per cluster, not once per message.
- **Many Replies** — one intent fans out into N individually voice-matched, individually addressed drafts.

The interaction model is a secretary briefing a busy executive: *"Three people want Monday at 2. You're booked. How do you want to handle all of them?"*

**Batched, not real-time.** Clustering is only possible if messages accumulate. Real-time notification per message structurally prevents the core mechanic and reproduces the original problem. The briefing is a scheduled event.

---

## 3. Scope — v1

### In Scope
| Capability | Channels |
|---|---|
| Full read + send | Email (Gmail / Outlook), SMS |
| Read-only triage | System notifications (Android), incl. social/messaging apps |
| Calendar extraction | All triaged messages |
| Voice-matched drafting | All channels |

### Out of Scope (v1)
- Automated sending on any social platform (ToS risk — deliberately excluded)
- iMessage on non-Mac environments
- Screen recording / OCR capture (deferred, see §8)
- Multi-user / team features

### Explicit Non-Goal
The assistant never sends anything on a social platform. For notification-sourced messages it produces a draft the user copies into the native app manually. This keeps the system read-only with respect to third-party platforms.

---

## 4. System Architecture

### 4.1 Layers

```
   ┌──────────────────────────────────────────────┐
   │  INGESTION                                   │
   │  · Gmail / Outlook API      (read + send)    │
   │  · Android SMS (default-app) (read + send)   │
   │  · NotificationListener      (read-only)     │
   └───────────────────┬──────────────────────────┘
                       ▼
   ┌──────────────────────────────────────────────┐
   │  NORMALIZATION                               │      ╔═══════════════════════╗
   │  → Message object                            │◀────▶║   PERSISTENT STATE    ║
   │  → handle resolved to Contact  (§4.2)        │      ║                       ║
   └───────────────────┬──────────────────────────┘      ║  · Contacts           ║
                       ▼                                 ║    (tier, register,   ║
   ┌──────────────────────────────────────────────┐      ║     deferrals)        ║
   │  TRIAGE ENGINE                               │◀────▶║                       ║
   │  · Classify (reply / calendar / fyi / noise) │      ║  · Registers          ║
   │  · Urgency score (consumes tier + deferrals) │      ║    (voice profiles)   ║
   │  · Calendar-intent extraction                │      ║                       ║
   └───────────────────┬──────────────────────────┘      ║  · Decisions          ║
                       ▼                                 ║    (prior intents)    ║
   ┌──────────────────────────────────────────────┐      ║                       ║
   │  CLUSTERING ENGINE                           │◀────▶║  · Calendar cache     ║
   │  · calendar_conflict / same_question /       │      ║    (events + classes) ║
   │    same_decision                             │      ║                       ║
   │  · applies prior Decisions       (§5A.4)     │      ╚═══════╤═══════════════╝
   │  · reads Calendar + Displacement (§5B.2)     │              ▲
   └───────────────────┬──────────────────────────┘              │
                       ▼                                         │
   ┌──────────────────────────────────────────────┐              │
   │  BRIEFING (scheduled — AM / PM)              │              │
   │  · Ordered clusters, summary + expand        │              │
   │  · Displacement recommendations              │              │
   │  · Tier prompts for UNTIERED contacts        │              │
   │  · Escalations, adjustment suggestions       │              │
   └───────────────────┬──────────────────────────┘              │
                       ▼                                         │
   ┌──────────────────────────────────────────────┐              │
   │  INTENT CAPTURE — one answer per cluster     │              │
   │  → creates Decision                          │──────────────┤ writes Decision
   └───────────────────┬──────────────────────────┘              │
                       ▼                                         │
   ┌──────────────────────────────────────────────┐              │
   │  VOICE ENGINE  (fan-out — one per recipient) │              │
   │  · register + modifier per Draft             │              │
   │  · hybrid routing: on-device / cloud         │              │
   │  · near-duplicate check across cluster       │              │
   │  · register-mismatch check       (§6.2.5)    │              │
   └───────────────────┬──────────────────────────┘              │
                       ▼                                         │
   ┌──────────────────────────────────────────────┐              │
   │  REVIEW & DISPATCH                           │              │
   │  · Send (email / SMS)                        │              │
   │  · Copy-to-clipboard (notification-sourced)  │              │
   │  · Defer  → increments deferral_count        │──────────────┤ writes Contact
   │  · Edits  → register refinement    (§6.4)    │──────────────┘ writes Register
   └──────────────────────────────────────────────┘
```

The three write-backs on the right are not optional polish — they are what make the system improve rather than repeat itself.

### 4.2 Data Model

The pipeline is stateless per-run; **all durable behavior lives on `Contact`**. Tiers, registers, deferral counters, and split flags are contact-scoped, not message-scoped. This is the single most important structural fact in the system: a message is transient, a contact is permanent.

```
Contact {
  id
  display_name
  handles[]            // email addrs, phone numbers, app handles — many-to-one
  tier                 // T1 | T2 | T3 | T4 | UNTIERED (default)
  register_id          // nullable → falls back to Formal (§6.2.5)
  always_individual    // true = never cluster this contact (§5A.3)
  deferral_count       // consecutive briefings deferred (§5B.4)
  last_replied_at      // feeds reply-latency signal
  reply_latency_avg
}
```

Handle-to-contact resolution is non-trivial and load-bearing: the same person appears as an email address, a phone number, and a WhatsApp notification name. If these don't merge into one `Contact`, tiers and registers fragment and the priority model silently fails.

```
Message {
  id
  contact_id           // resolved at normalization; the critical join
  source               // gmail | outlook | sms | notification
  source_app           // "instagram", "whatsapp", null
  body                 // subject to retention policy (§4.4)
  received_at
  thread_id            // nullable
  is_truncated         // true for most notification captures
  can_reply_direct     // enforces no-auto-post rule
  classification       // needs_reply | needs_calendar | fyi | noise
  urgency_score
  cluster_id           // nullable
}

Cluster {
  id
  type                 // calendar_conflict | same_question | same_decision
  message_ids[]
  decision_id          // nullable until user answers
  proposed_at
}

Decision {
  id
  intent_text          // the user's raw fragment
  resolved_at
  scope                // e.g. {slot: "Mon 14:00-16:00", answer: "unavailable"}
  expires_at           // when it stops auto-applying (§5A.4)
}

Draft {
  id
  message_id
  decision_id
  register_id
  modifier             // routine | apologetic | declining | ...
  generated_by         // on_device | cloud
  confidence
  body
  status               // pending | edited | sent | dismissed
}
```

`Decision` is the entity the product is named after ("One Decision, Many Replies") and must be first-class — it is what persists across briefings, enables intent reuse (§5A.4), and is the parent of the fan-out.

### 4.3 The Pipeline Is Not Purely Linear

The v1 diagram implied a one-way pipe. It isn't. Three feedback edges are load-bearing:

- **Draft edits → Register profiles** (§6.4) — the learning loop
- **Deferrals → Contact state** (§5B.4) — escalation tracking
- **Decisions → Clustering** (§5A.4) — prior decisions pre-resolve future clusters

Additionally, **Clustering reads Calendar state**, which is not an ingestion source but a queryable store. Calendar-conflict clusters cannot be formed without it, making Calendar a dependency of Clustering rather than a downstream consumer.

Practically: build a **persistent state store** (Contacts, Decisions, Registers, Calendar cache) that the pipeline reads from and writes back to. Treating this as a linear pipeline is the single most likely way to build it wrong.

### 4.4 Retention Policy

Per §10.1B, message bodies are not archived. But two committed features need body text after ingestion:
- Draft generation consumes recent thread history (§6.3)
- Register profiles are trained on sent-message corpus (§6.1)

**Policy:**
| Data | Retention |
|---|---|
| Message body — active thread | Rolling window, last ~10 messages per thread |
| Message body — resolved/dismissed | Discarded |
| Message metadata | Retained |
| Sent-message corpus | Retained during profile training, then discarded — profiles persist, source text does not |
| Contact, Decision, Register, Draft state | Persistent |

---

## 5. The Triage Engine

Triage runs before the user ever sees anything. Its output determines queue order.

### Classification
Each message is tagged:
- **Needs reply** — a question, request, or social obligation is pending
- **Needs calendar action** — a date, time, or commitment is proposed
- **FYI** — informational, no action
- **Noise** — marketing, automated, notifications-about-notifications

Only *Needs reply* and *Needs calendar action* enter the briefing queue.

### Urgency Scoring

**Urgency consumes `Contact` state — it does not compute its own parallel importance model.** An earlier version of this doc had triage independently learning "sender importance" from reply latency while §5B.4 simultaneously governed tiers. Two systems ranking the same people by different logic would drift apart and produce contradictory ordering.

Composite score from:
- Explicit time pressure in the message body ("by tomorrow", "EOD")
- Age of message (older unanswered = higher — this is the core user problem)
- `contact.tier` — read, never inferred here (tier changes are manual, §5B.4)
- `contact.deferral_count` — the single source of truth for repeat-avoidance escalation (§5B.4)

Reply-latency history still exists, but only as an input to *suggested* tier promotions in §5B.4. It never feeds urgency directly.

### Calendar Extraction
When a date/time commitment is detected, the system proposes a calendar event alongside the reply draft. User confirms both in one action — this directly addresses the second half of the stated problem.

---

## 5A. The Clustering Engine

The mechanism that makes batching more valuable than real-time, not just less intrusive.

### 5A.1 Cluster Types

**Calendar-conflict clusters**
Multiple messages proposing the same or overlapping time slot. The system checks the user's actual calendar *before* the briefing, so the cluster arrives pre-resolved: "Four people want Monday afternoon. You have a commitment 1–4pm."

This is the highest-value cluster type because the answer is determined by the calendar, not by the sender — the user is confirming a fact he already knows, not making four separate judgment calls.

**Same-question clusters**
Different people asking substantively the same thing ("are you coming Saturday?", "you in for the weekend thing?"). One answer, N drafts.

**Same-decision clusters**
Different questions that resolve to one underlying decision. Three separate requests that all depend on whether the user is traveling that week collapse into: "Are you going to be in town the 14th–18th?"

### 5A.2 Fan-Out Rule (Critical)

**One intent produces N drafts. It never produces one message sent N times.**

Each draft is independently generated with that specific recipient's relationship calibration, thread history, and appropriate register. The shared element is the *decision*; the wording is not shared.

Failure mode this prevents: three friends compare texts and find identical wording. That single event destroys the product's core premise — that replies are indistinguishable from the user's own.

Enforcement: the voice engine receives the intent once but runs generation per-recipient, and drafts within a cluster are checked against each other for near-duplicate phrasing before presentation.

### 5A.3 Clusters Are Proposals, Not Commitments

Clustering is inference and will sometimes be wrong. Two people asking for Monday 2pm may warrant different answers — the user might move a commitment for his co-founder but not for an acquaintance.

Therefore:
- Every cluster is presented with its member messages visible
- The user can split a message out of a cluster and answer it individually
- The system learns from splits: if a specific contact is repeatedly split out, that contact is flagged as always-individual

**Design bias: under-cluster rather than over-cluster.** A missed cluster costs one extra question. A wrong cluster sends someone the wrong answer.

### 5A.4 Intent Reuse Across Briefings

A decision made in one briefing ("I'm booked Monday afternoon") persists as context. A message arriving the next day proposing Monday 2pm joins the existing decision and can be pre-drafted, surfaced for confirmation rather than fresh input.

---

## 5B. Priority & Displacement Model

Determines whether an existing commitment can be moved to accommodate an incoming request. Governs calendar-conflict clusters (§5A.1).

### 5B.1 Two Independent Axes

The common mistake is treating "important" and "movable" as one variable. They are not.

**Axis 1 — Contact Tier (who is asking)**
User-defined, explicitly set per contact:

| Tier | Examples | Behavior |
|---|---|---|
| T1 — Critical | Investors, side-job employer | Displaces almost anything; never batched into a generic cluster |
| T2 — High | Co-founder, key collaborators | Displaces T4 and below |
| T3 — Standard | Friends, regular contacts | Displaces T4 |
| T4 — Low | Acquaintances, loose social | Displaces nothing |
| **UNTIERED** | Default state; not yet assigned | Displaces nothing. Prompts for assignment on first briefing appearance (§10, Q10) |

**Axis 2 — Commitment Class (what is already booked)**
Set per event or inferred by category:

| Class | Meaning | Examples |
|---|---|---|
| Fixed | Cannot move regardless of who asks | Side-job shift, investor meeting, flight |
| Group-locked | Low personal stakes but others coordinated around it; moving it costs social capital | Volleyball with friends, group dinner |
| Flexible | Can be rescheduled with minimal cost | Solo gym session, errands, optional social |
| Soft | Placeholder or tentative | Unconfirmed plans, "maybe" events |

**Key insight:** Group-locked is the class that breaks a single-priority system. Volleyball is not high-stakes, but four people arranged their day around it. Priority alone would move it; commitment class correctly protects it.

### 5B.2 Displacement Rule

```
Can incoming request displace existing commitment?

Fixed          → Never. Decline regardless of tier.
Group-locked   → Only T1. Everything else declines.
Flexible       → T1, T2, T3. Propose reschedule of existing.
Soft           → Any tier, including UNTIERED. Propose reschedule.

UNTIERED contact → treated as T4 (displaces nothing) until assigned.
                   Briefing prompts for tier before the recommendation
                   is finalized, so the user can override in place.
```

Output is a *recommendation* surfaced in the briefing, never an automatic calendar change. The user confirms.

**Unclassified commitments** (calendar events with no class assigned) default to **Fixed**. Same fail-safe logic as register assignment: wrongly protecting a movable event costs one manual override, wrongly moving a Fixed one costs a missed obligation.

### 5B.3 Why "Going/Maybe" RSVP Status Is Not Used

Considered and rejected as a movability signal. RSVP status reflects intent at the moment of marking, not current commitment strength — a user may mark "going" and later reconsider. Commitment class is set as a property of the event type, which is stable, rather than inferred from a stale interaction.

### 5B.4 Dynamic Adjustment — What Learns and What Doesn't

**Repeated deferral escalates. It does not demote.**

Deferral is an avoidance signal, not an unimportance signal. The user's core problem is non-response; a system that demotes whatever gets postponed would systematically bury the highest-stakes items — difficult conversations, intimidating contacts, obligations carrying anxiety — while reporting that the queue is clear. This inverts the product's purpose.

Therefore:
- 3+ deferrals of the same contact → **surfaced at the top of the briefing** with the deferral count visible
- Escalation is informational, not coercive. The user may consciously downgrade the contact's tier, which is a deliberate act rather than a silent inference.

**What does adjust automatically:**

| Signal | Adjustment | Rationale |
|---|---|---|
| Contact repeatedly split out of clusters | Flag as always-individual | Behavioral, unambiguous |
| Consistently fast replies to a contact | Suggest tier promotion | Reply latency is a strong revealed-preference signal |
| Commitment of a category repeatedly rescheduled by the user | Suggest reclassifying that category as Flexible | The user's own actions define the class |
| Contact tier | **Manual only** | Too consequential to infer; investor vs. acquaintance is a fact the user knows |

All automatic adjustments are *suggestions presented in the briefing*, not silent changes. The user should never discover that the system quietly reprioritized someone.

---

## 6. The Voice Engine

This is the differentiating component. Everything else is plumbing.

### 6.1 Style Profile

Built from a corpus of the user's actual sent messages (sent email folder, SMS history). Profile captures:

| Dimension | Examples |
|---|---|
| Openers / closers | Does he say "Hey" or "Hi"? Sign off or not? |
| Message length | Typical word count by channel and by relationship |
| Punctuation habits | Ellipses, em-dashes, missing periods, lowercase starts |
| Vocabulary | Recurring phrases, filler words, idiosyncratic spellings |
| Emoji usage | Frequency, which ones, placement |
| Formality gradient | How tone shifts between work email and texts to friends |
| Directness | Hedging vs. blunt |

### 6.2 Register Architecture

The style profile is not one model with a tone dial. It is a set of **registers** — independently maintained voice partitions, each backed by its own slice of the corpus.

A tone dial applied to a single averaged profile produces a blurred voice that is slightly wrong everywhere. Partitioned corpora produce a voice that is precisely right within its domain.

#### Default Registers (v1)

| Register | Corpus source | Characteristics |
|---|---|---|
| **Professional** | Work email, investor threads, side-job comms | Full sentences, complete punctuation, no contractions dropped, explicit sign-offs, no slang |
| **Social** | Texts to friends, group chats | Fragments, lowercase starts, slang, "man"/"bro", minimal punctuation, no sign-off |
| **Family** | Messages to family contacts | Warmer than professional, cleaner than social; distinct closers |
| **Formal** | Cold outreach, unknown recipients, official | Most conservative; default fallback when uncertain |

#### User-Extensible

Registers are not a fixed enum. The user can create new ones as relationships emerge — a partner, a specific client, a new co-founder. Creating a register requires:
1. A name
2. An assignment rule (specific contacts, or a contact group)
3. A corpus source — either existing history with those contacts, or a nearest-register bootstrap (§6.2.2)

#### 6.2.1 Registers Are Orthogonal to Contact Tiers

These are separate axes and must not be collapsed:

- **Tier** (§5B.1) answers: *whose request wins a scheduling conflict?*
- **Register** answers: *how do I sound when I write to them?*

A side-job employer may be T1 (Critical) and Professional. A close friend may be T3 and Social. A family member may be T3 but requires its own Family register. An investor is T1 and Professional. There is no reliable mapping from one to the other — both are assigned independently per contact.

#### 6.2.2 Cold-Start Problem

A new register has no corpus. Handling:

1. **Nearest-register bootstrap** — inherit from the closest existing register (a new client starts from Professional) and diverge as real history accumulates
2. **Explicit sampling** — user supplies 5–10 representative messages, or answers a short calibration set ("how would you cancel on this person?")
3. **Accelerated learning** — edits within a young register weight more heavily than in a mature one

Until a register has sufficient history, drafts in it are flagged as low-confidence and always require review.

#### 6.2.3 Situational Modifiers

Register sets the baseline voice. Context adjusts within it. The same person receives different treatment for casual logistics versus bad news versus an apology.

Modifiers layer on top of a register rather than overriding it — an apology in Social register still sounds like the user's social voice, just contrite. Modifiers include: routine, apologetic, declining, celebratory, bad news, urgent.

#### 6.2.4 Cross-Register Clusters

A cluster can span registers. If the user is double-booked Monday at 2, the same decision may need to go to a volleyball friend and an investor simultaneously.

One intent → drafts generated in **different registers** for the same cluster. This is the strongest case for the per-recipient fan-out rule (§5A.2): the drafts must not merely differ in wording, they must differ in voice entirely.

Cross-register clusters are visually grouped by register in the briefing so the user can see at a glance that the investor draft does not read like the friend draft.

#### 6.2.5 Misassignment Safeguards

Sending a Social-register message to a T1 professional contact is a severe, potentially relationship-damaging failure. The reverse — overly formal to a friend — is minor.

Because the risk is asymmetric, the system fails toward formality:

- **Uncertain register → default to the more formal option**, never the more casual
- **Unknown/new contacts → Formal register** until explicitly assigned
- **Register downgrades require confirmation** — assigning a contact from Professional to Social prompts the user
- **T1 contacts** — drafts always show the active register label and require explicit review before send
- **Register-mismatch detection** — if a draft contains markers strongly associated with a different register (slang in a Professional draft), it is flagged before presentation

### 6.3 Draft Generation

Input: `intent fragment` + `original message` + `register (per-recipient)` + `situational modifier` + `recent thread history`
Output: a complete message ready to send.

**Quality bar:** A third party reading the message should not be able to tell it was AI-drafted. Test method — blind A/B: mix generated drafts with the user's real historical replies and check whether the user himself can distinguish them.

### 6.4 Feedback Loop

Every user edit before sending is a training signal. If the user consistently shortens drafts, the profile adjusts toward brevity. This is the mechanism by which the voice sharpens over time.

---

## 7. Platform Reality Matrix

| Channel | Read | Send | Method | Notes |
|---|---|---|---|---|
| Gmail | ✅ | ✅ | Gmail API | OAuth, well-documented |
| Outlook | ✅ | ✅ | Microsoft Graph | OAuth |
| SMS (Android) | ✅ | ✅ | Android SMS/Telephony API | Requires default-SMS-app role for full access |
| SMS (via Twilio) | ✅ | ✅ | Twilio API | Requires a new number; clean but changes user's number |
| iMessage | ⚠️ | ⚠️ | macOS AppleScript / Shortcuts | Mac-tethered only; no iOS path |
| Social/chat apps (Android) | ✅ read-only | ❌ | NotificationListenerService | Truncated bodies; draft-and-copy only |
| Social/chat apps (iOS) | ❌ | ❌ | — | No API access to other apps' notifications |

### The iOS Problem
iOS does not permit third-party apps to read other apps' notification content. There is no workaround within App Store rules. **Consequence:** on iOS, v1 is email + SMS only. Full-spectrum triage is an Android-first capability.

**Decision: Android-first.** Effectively settled by two later decisions — Q1 (default-SMS-app role, Android-only) and Q3 (on-device drafting on a Samsung device). Both assume Android; the doc previously left this marked "decision required" while depending on it throughout. Recorded here explicitly.

iOS is a post-v1 question and would ship a materially reduced product: email only, no notification triage, no SMS.

---

## 8. Deferred: Screen Capture / OCR

Screen recording with OCR was considered as an iOS workaround and as a way to recover full message bodies where notifications truncate.

**Deferred from v1 because:**
- Brittle — breaks whenever a platform's UI changes
- Battery and performance cost of continuous capture
- Elevated ToS exposure relative to notification reading
- High implementation cost for a fallback path

**Revisit if:** notification truncation proves to make triage unusable in practice, or iOS parity becomes a launch requirement.

---

## 9. Phased Build Plan

### Phase 1 — Prove the Voice Engine
The riskiest assumption is that AI can write convincingly as the user. Test it before building any infrastructure.

- Partition the corpus of sent messages by register
- Build Professional and Social register profiles (the two most distinct — if these can't be separated, nothing finer will work)
- Generate drafts from intent fragments against real historical messages in both registers
- Run the blind A/B test (§6.3) **per register**

**Gate:** If drafts are not convincingly the user's voice — or if the two registers are not audibly distinct from each other — the entire product premise fails. Do not proceed until this passes.

### Phase 2 — Single-Channel Vertical Slice (Batched From Day One)
- Gmail only, read + send
- Persistent state store, Contact resolution, Message/Draft entities
- Triage engine, **manually-triggered briefing** over accumulated messages
- Register assignment UI + misassignment safeguards (§6.2.5)
- Intent capture → draft → review → send

**Batched from the start — no per-message prompting is ever built.** An earlier plan had Phase 2 ship real-time prompting and Phase 4 replace it. That is throwaway work, and worse, its gate would have validated the exact interaction model §2 rejects. A manual "run my brief now" button over accumulated email is cheap, survives into every later phase, and tests the real model. Only the *scheduling* is deferred.

Register assignment moves here because §6.2.5 safeguards are meaningless if drafting exists before registers can be assigned.

**Gate:** User clears his email backlog over two weeks using briefings only.

### Phase 3 — Calendar + Priority Model
Ahead of multi-channel: calendar-conflict clustering is the highest-value cluster type and depends on calendar state.

- Calendar read access + Calendar cache in state store
- Calendar-intent extraction from messages
- Contact tiers (default UNTIERED, prompt on first briefing appearance)
- Commitment classes (hybrid: system proposes, user confirms; unclassified → Fixed)
- Displacement rule producing recommendations
- One-tap event creation alongside reply approval

**Gate:** A real scheduling conflict is correctly resolved without the user opening the calendar app.

### Phase 4 — Clustering + Scheduled Briefings
- Clustering engine (calendar-conflict first, then same-question, then same-decision)
- Decision entity + intent reuse across briefings (§5A.4)
- Scheduled AM/PM briefings replacing manual trigger
- Fan-out generation with near-duplicate checking
- Cluster split UI

**Gate:** At least one cluster resolves 2+ messages with a single answer, and the resulting drafts are visibly different from each other.

### Phase 5 — Multi-Channel Ingestion
- Add SMS (resolve §10.1C default-SMS-app / notification-ownership question **before** starting)
- Add Android notification listener (read-only, draft-and-copy)
- Handle-to-Contact merging across channels — the same person as email + phone + app handle must resolve to one Contact, or tiers and registers fragment

**Gate:** Queue feels like one inbox, not three bolted together, and no contact appears twice.

### Phase 6 — Learning Loop
- Edit-based register refinement (§6.4)
- Suggested tier promotions from reply latency
- Suggested commitment-class reclassification from reschedule behavior
- Always-individual contact flagging from split behavior
- On-device port + measured quality delta vs. cloud (§10.1A); settle routing rule

---

## 10. Resolved Decisions

| # | Question | Decision |
|---|---|---|
| 1 | SMS approach | **Default-SMS-app role.** Keep existing number — it's used for both business and personal. Full message access is the point of the product, not a side effect. |
| 2 | Corpus scope | **Full history, all channels.** Comprehensive context is the premise; a user opting into this product is opting into that. |
| 3 | Drafting location | **Hybrid: cloud for validation and heavy lifting, on-device as the target runtime.** Phase 1 proves the voice engine on a frontier cloud model — the hardest test needs the strongest model available. Cloud API remains available as an ongoing fallback path (harder register separations, low-confidence new registers per §6.2.2, model updates) even after on-device rollout. See §10.1 tension. |
| 4 | Storage policy | **Discard message bodies.** Messages already persist in the native SMS/email apps; duplicating them wastes storage. See §10.1 tension. |
| 5 | Briefing cadence | **Twice daily, differentiated.** Evening = next-day calendar and scheduling decisions. Morning = replies and message triage. |
| 6 | User ignores briefing | Deferred. Revisit after real usage data. |
| 7 | Urgent-message bypass | **No bypass. Skip entirely.** Native apps still deliver notifications for genuinely urgent items. This product is an additional layer for staying on track, not a replacement for the messaging apps. Replying the traditional way remains valid. See §10.1 tension. |
| 8 | Cluster presentation | **Summary with expand-to-full.** Default to condensed; full text available on demand. |
| 9 | Commitment class assignment | **Hybrid.** System proposes a class; user confirms or rejects with a single tap. |
| 10 | Tier setup | **No default tier.** Contacts start untiered. On first interaction through the briefing, the user must assign a tier, which then persists. Avoids both upfront config burden and silent miscategorization. |
| 11 | Escalation ceiling | **Intensifies, no plateau.** Three deferrals is a warning; six is a damaged relationship. Escalation must keep rising because the cost of continued non-response keeps rising. |

### 10.1 Tensions Introduced by These Decisions

**A. On-device vs. cloud — resolved as hybrid, with a routing question left open**
The Phase 1 bar is that drafts are indistinguishable from the user's own writing — the hardest thing this system does. Proving that on an undersized local model risked a false negative on the whole premise. Resolved: validate on the strongest cloud model first, then port down and measure the on-device quality delta explicitly.

Cloud remains available afterward as a fallback tier, not just a bootstrap step. Likely fallback triggers: a register too new/sparse to trust locally (§6.2.2), a T1-contact draft where the stakes justify the strongest available model regardless of latency or cost, or an on-device confidence score below threshold.

**Remaining question:** what decides per-draft whether cloud or on-device runs? Options — always on-device except explicit low-confidence escalation; always cloud for T1 contacts regardless of confidence; or a user-set default with manual override per draft. This should be settled during Phase 1, once real quality-delta data exists to inform it.

**B. "Discard everything" conflicts with features already specified**
Several committed features require persistence:
- Style profiles (§6) — derived from corpus, must persist
- Deferral counts (§5B.4) — requires tracking across briefings
- Intent reuse across briefings (§5A.4) — requires remembering decisions
- Contact tiers and commitment classes — persistent by definition

**Resolution:** Discard *message bodies* after processing. Retain *derived state*: style profiles, tiers, classes, deferral counters, decision context, and message metadata (sender, timestamp, thread ID). This honors the intent — no duplicate message archive eating storage — while keeping the system functional.

**C. Q7's answer assumes the native app is separate — Q1 may break that**
The reasoning for skipping urgent-bypass is that the native SMS app still shows notifications. But taking the default-SMS-app role (Q1) can mean *this app becomes* the SMS app, inheriting notification responsibility.

**Resolution required.** Options:
1. Take default-SMS-app role and faithfully reproduce standard notification behavior — user gets normal pings plus the briefing layer
2. Read SMS without taking the default role (more limited access on modern Android) and leave the native app untouched

Option 1 preserves the intended experience but means building conventional messaging notifications, which is real scope. This should be settled before Phase 5.

**D. Hybrid routing partially undoes the privacy motivation for on-device**
On-device was chosen partly out of preference for local processing. Hybrid routing (Q3) means that in exactly the highest-stakes cases — T1 contacts, sparse registers — message content leaves the device.

This is a real trade, not a technicality. The most sensitive drafts are the ones most likely to be routed to cloud.

**Needs a conscious call, not a default.** Options:
1. Accept it — quality matters most where stakes are highest
2. Hard-cap: certain contacts or registers are marked local-only regardless of confidence, accepting lower draft quality
3. Cloud only during Phase 1 validation; strictly local in production once the delta is measured and judged acceptable

Option 2 is the only one that preserves the original privacy intent while keeping hybrid's benefits, and it fits the existing per-contact model cleanly — a `local_only` flag on `Contact`.

---

## 11. Remaining Open Questions

1. **Register assignment burden** — assigned per contact manually, inferred from channel/history, or proposed during onboarding from corpus clustering?
2. **Corpus partition boundaries** — how is unlabeled historical data split into registers at setup? Contact-based inference misfiles anyone contacted across contexts.
3. **Same contact, multiple registers** — a friend who becomes a business partner may need Social for logistics and Professional for deal terms. Per-contact or per-thread?
4. **Tier prompt timing** — with no default tier (Q10), does the first-run backlog produce a wall of tier prompts? Likely mitigation: only prompt when a contact actually surfaces in a briefing, spreading setup over natural use.
5. **On-device/cloud routing rule** — what decides per-draft which runtime is used? Deferred to Phase 1, once quality-delta data exists (§10.1A).
6. **Local-only enforcement** — adopt the `local_only` contact flag from §10.1D, and if so, is it user-set or automatic for T1?
7. **Decision expiry** — how long does a Decision keep auto-applying to new messages (§5A.4)? Too short loses the benefit; too long applies a stale answer after plans change.
8. **Near-duplicate threshold** — what similarity level triggers a regeneration in §5A.2, and does it relax for cross-register clusters where drafts are already highly dissimilar?
9. **Contact merge conflicts** — when handle resolution is ambiguous (shared family email, work vs. personal address), does the system ask or guess?

---

## 12. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| On-device model underperforms cloud for high-stakes drafts | Medium | Hybrid routing — cloud fallback for T1 contacts, sparse registers, low-confidence drafts (§10.1A) |
| Voice engine unconvincing | **Critical** | Phase 1 gate before any other build |
| iOS platform limits | High | Android-first; accept reduced iOS scope |
| Notification truncation degrades triage | Medium | Truncated messages still surface *that* a reply is owed; user opens app for context |
| Hybrid routing sends message content off-device | High | Consequence of Q3 — see §10.1D. Requires conscious acceptance, not just a retention policy |
| Full-history corpus is extremely sensitive at rest | High | Retention policy (§4.4): bodies discarded after processing, corpus discarded after profile training |
| Register misassignment (social voice to investor) | **Critical** | Fail-toward-formal default; T1 drafts show register label and require review; mismatch marker detection (§6.2.5) |
| Registers not audibly distinct | **Critical** | Phase 1 gate tests separation, not just fidelity |
| Sparse corpus in new registers | High | Nearest-register bootstrap + explicit sampling; low-confidence flagging until mature |
| Near-identical drafts within a cluster | **Critical** | Per-recipient generation + duplicate-phrasing check (§5A.2) |
| Over-clustering sends wrong answer | High | Under-cluster bias; clusters are proposals; split-out always available |
| Auto-demotion buries avoided-but-important items | **Critical** | Deferral escalates rather than demotes (§5B.4); tier changes are manual only |
| Tier/class setup friction kills onboarding | High | No upfront config: contacts start UNTIERED and are prompted only when they surface in a briefing; classes proposed by system, confirmed in one tap |
| Handles fail to merge into one Contact | High | All durable state is contact-scoped; fragmented identity silently breaks tiers, registers, and deferral tracking (§4.2). Explicit Phase 5 gate. |
| Default-SMS-app role is large hidden scope | High | Becoming the SMS app means owning send/receive/notification UX; resolve §10.1C before Phase 5 |
| Silent reprioritization erodes trust | Medium | All automatic adjustments surface as briefing suggestions, never applied silently |
| User ignores the briefing | Medium | Single fixed daily event is a habit anchor; real-time nagging is worse |
| ToS exposure | Low (as scoped) | Read-only for social; no automated sending anywhere the platform prohibits it |
