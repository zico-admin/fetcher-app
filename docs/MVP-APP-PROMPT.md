# Prompt — Fetcher MVP, local only

Paste into a fresh Claude Code session in an **empty directory** (not this repo —
this one is the Terraform build). Everything below is self-contained; it does not
need FETCHER-BRIEF.md.

---

Build Fetcher: a local-only MVP of an app that tells a traveller where to eat and
what to order in a city they don't know, based on a health goal they set.

Runs entirely on my laptop. No cloud, no Terraform, no deployment, no accounts
with any provider. If a step would need a hosted service, use a local stand-in and
leave a comment naming what it stands in for.

## How I want you to work

- Explain non-obvious choices in a comment. I'd rather understand a real error
  than have you route around it silently.
- If I ask for something that's bad practice, push back before doing it.
- Build one milestone, then stop and wait for me.
- Before writing code, ask me anything genuinely ambiguous — all at once.

## The product

The user is a traveller managing weight or blood sugar who loses the thread the
moment they leave their routine. Every other app assumes you're home, shopping a
familiar store, cooking. Fetcher assumes you're on a street in an unfamiliar city
with ninety seconds of patience, and answers the only question that matters: where
do I go, and what do I order when I get there.

The output is a specific dish at a specific place plus the modification to ask for
— "get the bowl, sub brown rice, dressing on the side, skip the chips." That's
what a knowledgeable friend gives you and what no app does.

Seed city: Washington, DC. One city, but make `city` a first-class entity so the
second is cheap. One persona: adults managing weight or blood sugar who travel.

## Stack

- Next.js (App Router) + TypeScript in strict mode, pnpm
- SQLite via better-sqlite3, queried through Kysely — stands in for Postgres
- Zod for input validation, Vitest for tests
- Plain CSS or Tailwind, your call. Mobile web only; design for a phone
- No third-party analytics, tag managers, or fonts-with-telemetry on any page

For the one-line "why this" and the modification copy, call the Anthropic API
(`claude-haiku-4-5-20251001`) if `ANTHROPIC_API_KEY` is set, and fall back to a
deterministic template when it isn't. The app must run and pass tests with no key.

## Do not build — these are binding

- No health-record integration. No Apple Health, HealthKit, FHIR, lab values. If
  someone types a lab number into free text, do not parse or store it as
  structured health data.
- No native apps. Mobile web only.
- No body-fat, measurements, avatars, or 3D anything. Weight, height, age, sex and
  activity are in scope because the guardrail maths needs them; nothing else is.
- No pregnancy, allergy, or medical-condition modes. "Watching blood sugar" is a
  preference that shifts scoring weights — never a clinical mode, never glucose
  numbers.
- No accounts, passwords, OAuth, or email. Phone number plus a code, and in this
  build the code is printed to the server console.
- No calorie logging, food diary, streaks, or photo recognition. Fetcher is
  forward-looking. It never asks what you ate.
- No payments, partnerships, or booking.
- If a feature seems obviously useful and isn't listed, it's deliberately
  excluded. Raise it, don't add it.

## Confidence tiers — hard rules

Every nutrition figure carries a tier:

| Tier | Means | May show as | May satisfy a hard constraint |
|---|---|---|---|
| `verified` | Human-checked or venue-published | Exact figures | Yes |
| `menu_stated` | Menu names ingredients and preparation | Exact figures, sourced | Yes |
| `inferred` | Estimate from name and cuisine norms | Range only, labelled an estimate | No |
| `unknown` | Not enough to go on | No numbers, qualitative only | No |

These are not display preferences. Enforce them in the **type system**: an
`inferred` or `unknown` row must be structurally incapable of rendering as a
precise number or clearing a hard filter. The function that renders an exact
figure, and the one that applies a hard constraint, accept only the first two
tiers — so a leak is a compile error. Write tests that fail if it leaks anyway.

When you generate seed data, anything you invent is `inferred`. Do not label
invented numbers `verified` — that's the one failure that would make the whole
tier system theatre.

## The pace guardrail

The user states a goal in their own words: "lose 15 pounds in one month." Accept
it, then translate it visibly.

- Compute the implied rate.
- Cap the coached rate at the lesser of 2 lb/week or 1% of body weight per week.
- If the stated rate exceeds the cap, show the translation before proceeding:

  > You asked for 15 lb in 4 weeks — about 3.8 lb a week. Fetcher plans at up to
  > 2 lb a week, so it's aiming you at 15 lb by [date]. Faster than that mostly
  > costs you muscle and tends not to stick.

- Never produce a plan whose implied daily intake falls below 1,500 kcal/day
  (male) or 1,200 kcal/day (female). Cap and say so.
- Store `stated_target`, `stated_deadline`, `coached_rate_lb_per_week`,
  `coached_deadline`, `guardrail_applied`. The user keeps their original target as
  an aspiration; the engine plans to the coached rate.

This is a visible feature with real copy, not a hidden clamp.

**Copy rules, enforced by a lint script that fails the build:** no
remaining-allowance framing; no streaks or badges on restriction; no moral
vocabulary for food ("clean", "cheat", "guilt-free"); and nothing that claims to
cure, detox, flush, or prevent a hangover. Standing line in the footer: Fetcher
isn't medical advice.

## The recommendation engine

Ranking is a deterministic, pure, unit-tested function. Not an LLM call.

```
candidates
  → hard filters   (open now, radius, price, dislikes, restriction-safe
                    using only verified/menu_stated rows)
  → score          (goal fit, protein & fibre density, refined-carb and fried
                    penalties, portion risk, distance decay, confidence bonus)
  → diversify      (one venue per cuisine; at most one chain)
  → top N
```

Input: profile, lat/lng, timestamp, meal context, optional event context, radius,
price ceiling. Output: 3–5 venues, each with distance, price level, open-now
status, 1–2 dishes, a one-line why, the modification line, and a confidence badge
per dish.

The LLM writes the why and the modification from the already-ranked row. It never
reorders. Keep the weights in one named, commented config object, and store the
full scoring breakdown for every recommendation served — when one is bad you need
to know whether the data, the weights, or the copy failed.

No venue rating in the scoring function (licensing — ratings come from a source
whose terms don't allow storing them).

Flags per dish: `high_protein`, `high_fiber`, `refined_carb_base`, `fried`,
`cream_or_butter_sauce`, `sugar_sweetened`, `large_format`, `vegetable_forward`,
`raw_or_undercooked`.

**Empty state matters more than it sounds.** Never widen the search silently. Say
what was found and how far: "Nothing within 10 minutes fits; the nearest good
option is X, 18 minutes away." An `inferred` row never gets promoted to fill a gap.

## Decisions already made — don't re-litigate

- Goal intake is web only, never over SMS. The guardrail copy needs the room.
- Trips are **declared**, not detected. A trip ends after N days idle; a second
  trip is a new one starting ≥ 14 days after the last ended.
- Phone number is the only identifier. No name, email, or address. Events are
  keyed by a pseudonymous user id so deletion is one predicate.
- One-tap delete that actually deletes, including events.

## Milestones — stop after each

1. **Schema, seed, scoring.** SQLite schema, migrations, 25–30 DC venues with
   menu items as fixtures, the scoring function, and tests. No UI. Done when
   `pnpm test` passes and a script ranks the seeded set from the command line.
2. **Goal intake and the guardrail.** Onboarding, the pace translation with real
   copy, the copy lint script. Done when an aggressive goal is visibly translated
   rather than silently clamped.
3. **Recommendation UI.** The card: dish, why, modification, confidence badge.
   Done when it's usable one-handed at 390px wide.
4. **Fake SMS console.** A dev-only page that simulates the texting loop —
   understands a bare city name, "hungry", "dinner", "going out tonight", "where
   now", "STOP". Replies are two or three options plus a link. Plus event mode:
   dinner weighted to protein and fat with a water plan, and a morning-after
   breakfast weighted to eggs, salt, potassium and fluids.
5. **Local metrics page.** Events into a local table; `/admin/metrics` renders
   signups, recommendations per user, follow-through, and a second-trip curve.
   Ugly is fine. Missing is not.

Start by asking your questions. Then build Milestone 1 only, and stop.
