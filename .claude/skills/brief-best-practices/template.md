# BRIEF — <surface name>

> Law doc for <surface>, present-tense, no narrated history — git is the changelog. Amend
> Decisions and Boundary only with human confirmation; log the rationale. Dated working memory
> lives in `DELTA.md` / `DEVIATIONS.md` beside this file.

## Bar

<One sentence: what "shippable" means for this surface. The north-star "done.">

## Dimensions

The few axes "good" decomposes into. When this document doesn't cover a decision, resolve it in
favor of these.

- **<Dimension 1>** — <what it means here>
- **<Dimension 2>** — <…>
- **<Dimension 3>** — <…>

## Floors

The minimum on each dimension, *with how it's measured*. The gate, not the ceiling.

| Dimension | Floor (threshold + measurement) |
|---|---|
| <Dimension 1> | <minimum bar, and the check/tool/metric that proves it> |
| <Dimension 2> | <…> |
| <Dimension 3> | <…> |

## Oracle

The independent verifier — what runs, who judges, and **why it can't be gamed** (maker ≠ judge).

- **Pre-ship:** <the harness/judge that runs the Floors before ship>
- **Post-ship (live systems only):** <the telemetry/signals that confirm it stays good>

## Never — instant fail

- <Outcome that is always unacceptable, regardless of everything else>
- <…>
- Weakening a floor, or removing a failing item without a `DEVIATIONS.md` entry and a replacement.
- Asking the human to lower the bar.

## Decisions

Calls already made, so the agent never re-asks. **This section grows** — every answered question
becomes a permanent entry. Include the tradeoff/priority policy and standing assumptions.

- **Priority / tradeoffs:** <e.g. "security > latency; security may force a redesign, latency may not">
- **Assumptions:** <standing assumptions about the environment; revisit if they break>
- <Decision> — <the call, and one line of rationale> (<date>)
- <Decision> — <…> (<date>)

## Boundary — requires the human

The loop never crosses these; they batch to the human handoff.

- Publish: <push / PR / merge / deploy / release>
- Credentials: <live secrets, biometric-gated actions>
- Direction: <genuinely undecided product/architecture calls — accumulate as `blocked: needs N decisions`>
