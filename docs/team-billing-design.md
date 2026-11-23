# Team plan billing — technical design options

Refs #21

## Status

Product decision made 2026-11-22 (see "Resolved" below) on billing model
(usage-based, not seat-based). Still not implemented. This plugin repo
(`zerodb-claude-plugin`) is a thin client — it has no billing engine, no
notion of a "plan," and no dashboard. Everything below is about what the
**plugin** would need to do to cooperate with billing logic that must live
server-side (ZeroDB backend / AINative dashboard), plus the questions that
remain genuinely open.

## What #19/#20 already give this for free

With shared team memory (#19) and `/remember --team` (#20) implemented,
every team-scoped operation already:

- targets a distinct ZeroDB `project_id` (the team project), separate from
  the caller's personal project — so a credit ledger keyed by `project_id`
  on the backend already separates team spend from personal spend with no
  further plugin changes.
- tags the stored memory with `metadata.author` (the storing teammate's
  git identity) — so a per-member usage breakdown by author is already
  possible from data the plugin writes today, assuming the backend
  aggregates `zerodb_store_memory` / `zerodb_search_memory` calls by
  `(project_id, metadata.author)`.

That covers the "Credit consumption from team project counts against team
quota" and "Team admin can see per-member usage breakdown" acceptance
criteria at the data-attribution level. The aggregation, dashboard
rendering, and quota enforcement are backend/dashboard work, not plugin
work, and aren't addressed here.

## Resolved: billing model is usage-based, not seat-based

Product decision (2026-11-22): every paid ZeroDB tier above the $5
Starter/Hobbyist tier is, in effect, a team account — AINative does not
price or gate by headcount. The dimension that is priced and metered is
**usage** (storage, vector count, and credit consumption against the
account's `project_id`), not the number of distinct humans drawing on it.
Concretely:

- There is no per-seat price multiplier and no seat minimum/maximum tied
  to plan price. Any number of teammates can share a team project's
  `ZERODB_API_KEY` access; what's metered is the project's consumption,
  not how many people produced it.
- The free/personal trial tier is a separate, single-user product
  surface (today's `max_users: 1` tiers) — it is not "per-member inside a
  team." Joining a team project replaces it for that use, it doesn't
  compose with it.
- This resolves original question 1 (plan tiers and limits) and question
  5 (seat accounting) from the prior draft of this doc: tiers are not
  per-seat, and there is no seat count to account for. A member's
  `metadata.author` tag on team-scoped writes stays purely for
  **attribution/visibility** (so an admin can see who used what) — it is
  never used for seat counting or a per-seat cap.

**Caveat worth flagging, not silently resolving:** the live backend tier
config (`src/backend/app/api/admin/users.py`, `TIER_CONFIG` in
`subscription_service.py`, `billing_configuration.py`) already stores a
`max_users` field per tier (e.g. PRO: 5, BUSINESS: 20, ENTERPRISE: 10 —
note ENTERPRISE's stored value is actually lower than BUSINESS's, which
looks like stale/inconsistent data rather than an intentional policy).
Checked whether this is actually enforced as a billing gate: it is not —
the only real runtime enforcement of a `max_users` style cap is in
`real_time_engine.py`'s live-collaboration session connection limit, an
unrelated feature. The subscription-tier `max_users` value is stored and
returned by a few read endpoints but never checked against an actual
member/seat count anywhere in billing or auth. So today's code does not
contradict the usage-based decision above, but that stored field is now
known-vestigial for billing purposes and should not be used as the basis
for any future seat-gating logic. Cleaning it up (e.g. removing it from
`TIER_CONFIG` or repurposing it as a documentation-only "typical team
size" hint) is backend/product work, out of scope for this plugin repo
and not required to unblock plugin-side work below.

## Still-open product/business questions (block implementation)

These were not resolved by the usage-vs-seat decision and still need a
product call before plugin code is written against them:

1. ~~**Plan tiers and limits.**~~ Resolved above: usage-based, not
   per-seat.
2. **Overage behavior — simplified, not fully resolved.** Because billing
   is usage-based with no seat math, "overage" is now simply: has this
   `project_id`'s credit/usage consumption crossed its plan's quota? No
   per-seat or per-member reconciliation is needed. Still open: does the
   plugin need to degrade gracefully (e.g. `/remember --team` starts
   failing, or falls back to personal) once the team project is over
   quota, or is overage purely a backend/billing-side concern invisible
   to the plugin until a hard stop? If the plugin must surface overage
   state, what API does it call to check it, and on what cadence (every
   team op? session start only?)?
3. **Invite flow.** "Admin shares invite link → member connects their
   Claude Code to team project" — today `/memory team setup <team-project-id>`
   requires knowing the raw project ID and having `ZERODB_API_KEY` access
   to it already. Is the intended flow instead: admin generates an invite
   token/link from the dashboard → member runs something like
   `/memory team setup --invite <token>` → the plugin exchanges the token
   for a project ID *and* provisions/attaches the member's API key access
   to that project? That's a materially different (and bigger) piece of
   plugin work than what exists now, and needs a defined invite-token API
   before it can be built. (Note: since seats aren't metered or capped,
   the invite flow's job is purely access provisioning, not seat
   consumption — simplifies the token exchange but doesn't eliminate the
   need to design it.)
4. **Admin identity / permissions model.** Nothing in the plugin currently
   knows who is a "team admin" versus a regular member — that distinction
   (if it needs to affect plugin behavior at all, e.g. gating who can run
   `/memory team setup`) has to be defined by the backend's permission
   model first.
5. ~~**Seat accounting.**~~ Resolved above: there is no seat accounting
   for billing purposes. `metadata.author` tagging remains for
   per-member usage visibility only.

## If/when those are answered: likely shape of the plugin-side work

Sketched only so a future implementer has a starting point — none of this
should be built until questions 2–4 above are resolved:

- A `/memory team usage` (or similar) subcommand that calls a backend
  endpoint (does not exist yet) returning the team project's credit
  balance/quota (usage-based, no seat dimension), and renders it next to
  the existing `/memory stats` team section already added for #19.
- If overage must be surfaced client-side: a check (likely alongside the
  existing `zerodb_get_team_project_id` resolution in
  `lib/team-project.sh`) that session-start.sh or the `/remember --team`
  skill consults before a team-scoped write, with a defined fallback
  behavior (block vs. warn vs. fall back to personal) — behavior TBD per
  question 2 above.
- If an invite-token flow is adopted: a new `lib/team-invite.sh` (or an
  extension of `lib/team-project.sh`) that exchanges an invite token for
  a project ID via a backend endpoint (does not exist yet), analogous to
  how `lib/ensure-credentials.sh` already exchanges a trial signup for a
  personal project ID. This flow provisions access only — it has no seat
  count to decrement or check against.

## Non-goals of this document

- No pricing numbers, overage policy, or invite/permissions mechanics are
  finalized here — overage cadence, the invite-token API shape, and the
  admin permissions model are still product/business decisions pending
  question 2–4 above, and inventing them would risk shipping billing
  behavior nobody signed off on.
- No backend/dashboard implementation is proposed — this plugin repo
  cannot implement billing enforcement itself; it can only cooperate with
  a backend that does.
- No change to the live `max_users` tier-config field is proposed here —
  flagged as vestigial for billing purposes, but removing/repurposing it
  is backend/product work tracked separately, not blocking this plugin.
