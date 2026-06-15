# BRIEF — peer-to-peer transfer flow (worked example)

> Illustrative filled brief for a money-transfer surface — the seven slots on a non-visual,
> high-stakes informatics system. Content here is illustrative, not a real system spec.

> Law doc for the transfer flow, present-tense, no narrated history — git is the changelog. Amend
> Decisions and Boundary only with human confirmation; log the rationale. Dated working memory
> lives in `DELTA.md` / `DEVIATIONS.md` beside this file.

## Bar

A transfer settles **exactly once**, is **fully reconstructable from the audit log**, and **never
moves funds the sender did not authorize** — or it does not ship.

## Dimensions

- **Correctness** — balances and ledger entries are right for every path, including partial failure.
- **Idempotency** — a retried or duplicated request never double-moves funds.
- **Auditability** — every state transition is logged with enough context to reconstruct it.
- **Security** — only an authenticated, authorized sender can move their funds; inputs are validated.
- **Latency** — the user gets a confirmed/pending state fast enough to trust the action.

## Floors

| Dimension | Floor (threshold + measurement) |
|---|---|
| Correctness | Property tests assert balance conservation and no-negative-balance across randomized op sequences; the suite passes 100% in CI |
| Idempotency | Replaying any request with the same idempotency key yields one ledger effect; verified by a duplicate-submission integration test and a fuzz of concurrent dupes |
| Auditability | Every transfer emits a structured event; a staging replay reconstructs final balances from the event log alone (no DB state) |
| Security | AuthZ test matrix (owner / non-owner / expired token) all pass; input validation rejects malformed amounts/recipients; no secret in logs |
| Latency | p95 request→committed-state < 300ms, measured on the staging load profile |

## Oracle

- **Pre-ship:** property + integration suite in CI (the independent judge for Correctness/Idempotency);
  a fresh-context reviewer who did not write the change reviews the AuthZ matrix and the ledger math;
  a staging run against forked production state exercises the happy path and the partial-failure path.
- **Post-ship (live):** dashboards + alerts on ledger-imbalance count (must stay 0), duplicate-effect
  rate, authz-denial anomalies, and p95 latency. These are the continuing oracle for a live system —
  the harness was the proxy; production is the final gate.

## Never — instant fail

- Funds move without a matching, authorized request (silent or unauthorized transfer).
- A ledger that can go negative, or whose entries don't sum to a conserved total.
- A state transition that lands without an audit event.
- An unbounded retry, or a retry without an idempotency key.
- A secret in a log line, error message, or trace.
- Weakening a floor, or shipping a failing path without a `DEVIATIONS.md` entry and a replacement.
- Asking the human to lower the bar.

## Decisions

- **Priority / tradeoffs:** correctness > security > auditability > latency. Correctness and security
  may force a redesign; latency may not. Never trade an audit event for speed.
- **Assumptions:** the ledger is the source of truth, not the cache; the message bus is at-least-once
  (hence idempotency keys are mandatory, not optional).
- Idempotency key is required on every mutating request; absent key → reject, don't guess. (illustrative)
- Pending state is shown optimistically only after the request is durably enqueued, never before. (illustrative)

## Boundary — requires the human

The loop never crosses these; they batch to the human handoff.

- Publish: deploy to production, database migrations, feature-flag flips that expose the flow to users.
- Credentials: any live-key access (production DB, signing keys, KMS) — the loop verifies against
  staging/forked state, never production secrets.
- Direction: limit policy, fee structure, regulatory/compliance calls — accumulate as
  `blocked: needs N decisions` rather than guessing.
