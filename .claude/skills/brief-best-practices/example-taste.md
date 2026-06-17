# BRIEF — product landing-page hero (worked example)

> Illustrative filled brief for a **subjective/taste** surface — the seven concerns where the bar is
> "premium, clear, calm" and no automated check can decide quality, so the oracle is a blind
> human-judge quorum. The objective sibling is `example-payments.md`. Content here is illustrative,
> not a real system spec. This example also shows the optional **Final-acceptance coda** — a
> culminating whole-surface test that restates the Boundary as a gate.

> Law doc for the landing hero, present-tense, no narrated history — git is the changelog. Amend
> Decisions and Boundary only with human confirmation; log the rationale. Dated working memory
> lives in `DELTA.md` / `DEVIATIONS.md` beside this file.

## Bar

A first-time visitor understands **what the product does** and feels it is a **real, premium
product** within five seconds — calm, clear, on-brand — or it does not ship.

## Dimensions

- **Clarity** — a stranger can say what the product does and who it's for, unprompted.
- **Credibility** — it reads as a real, trustworthy product, not a template or a generic demo.
- **Calm / restraint** — one focal message; nothing competes; premium is quiet, never loud.
- **Brand fidelity** — type, color, and spacing resolve to the brand system; no off-system improvisation.
- **Performance & access** — it loads fast and is legible and operable for everyone (the objective floor under a visual surface).

## Floors

| Dimension | Floor (threshold + measurement) |
|---|---|
| Clarity | Blind five-second test: **≥ 4 of 5** fresh-context judges correctly state what the product does, given only the screenshot and no context |
| Credibility | Blind judge panel rates "feels like a real product I'd trust" **≥ 4/5 median**, and **zero** judges flag "looks like a template / generic AI output" |
| Calm | **One** primary CTA above the fold; **≤ 1** competing visual focal point; motion is at most one subtle entrance, **none** looping or autoplaying — asserted on the captured render |
| Brand fidelity | Every color/type/spacing value resolves to a brand token, asserted against the design-token source (not eyeballed); **zero** off-token values |
| Performance & access | LCP **< 2.0s** and CLS **< 0.1** on the mid-tier mobile profile (Lighthouse CI); WCAG **AA** contrast on all text (axe); fully operable by keyboard and screen reader |

## Oracle

The maker may not judge first impressions — you cannot un-see your own copy, so your read is
permanently biased (the exact failure the oracle exists to defeat).

- **Subjective gate — blind human-judge quorum.** Five fresh-context judges, ideally across
  different people/vendors who have never seen the page, each given **only** the screenshot and the
  clarity + credibility questions — no product context. Quorum, not one opinion; diversity in the
  panel defeats a single idiosyncratic taste and cannot be talked around.
- **Objective floors** run in CI (Lighthouse, axe, token-lint) — fail-closed, no human in the path.
- **Reference-anchored.** Place the captured hero beside the brand's reference frames and the top
  three admired peers; write `DELTA.md` — the ten most significant gaps ranked by impact; fix the
  top three; re-capture. The round closes only after the re-capture.
- **Post-ship (live).** The oracle extends into telemetry: hero bounce rate, scroll-past rate, and
  CTA click-through are the continuing signal that the first impression holds. The judge panel was
  the proxy; the live audience is the final gate.

## Never — instant fail

- It reads as a **template** or generic AI output — interchangeable with any other product's page.
- A stranger **cannot say what the product does** after five seconds.
- **More than one thing competes** for the eye; any autoplaying or looping motion; anything that
  performs instead of communicates.
- An **off-brand** color, typeface, or spacing value; an improvised token.
- Text **below AA contrast**, or content that fails keyboard / screen-reader operation.
- A **claim the product can't back** — a fabricated testimonial or invented metric.
- Weakening a floor, or shipping a failing element without a `DEVIATIONS.md` entry and a replacement.
- Asking the human to lower the bar.

## Decisions

- **Priority / tradeoffs:** clarity > credibility > brand-polish > visual flourish. Clarity and
  access may force a redesign; a flourish may not. **Between two designs, ship the calmer, clearer
  one** — restraint beats spectacle.
- **Assumptions:** the brand token system is the source of truth, not a local design choice; mobile
  is the primary viewport.
- Copy is owned by the brand voice guide; the hero never invents claims. (illustrative)
- One hero, one CTA; secondary actions live below the fold. (illustrative)

## Boundary — requires the human

The loop never crosses these; they batch to the human handoff.

- **Publish:** pushing the page live, DNS/CDN changes, anything visitor-facing.
- **Brand authority:** changing a brand token, the positioning statement, or the core claim — the
  loop proposes, the brand owner decides.
- **Tie-break & direction:** when the blind quorum splits, the human breaks the tie; genuine
  brand-direction unknowns accumulate as `blocked: needs N decisions`, never guessed.
- **Real-audience validation** beyond the proxy judges (actual target-audience testing) is the
  human's call.

---

## Final acceptance — the five-second test

Capture the hero exactly as a first-time visitor meets it on a mid-tier phone. Show it to someone
who has never seen the product for five seconds, take it away, and ask: *what does this do, and
would you trust it?* If they answer the first and lean yes on the second — with no template smell,
no second focal point, no off-brand note — the surface has done its job. Until then, iterate.

Then the brand owner looks; their read is the gate after the frame. And the gate after the owner is
the real one: a stranger in the target audience who stays past the fold.
