# Team plan billing — technical design options

Refs #21

## Status

Draft for product/eng discussion. Nothing in this document is implemented.
This plugin repo (`zerodb-claude-plugin`) is a thin client — it has no
billing engine, no notion of a "plan," and no dashboard. Everything below
is about what the **plugin** would need to do to cooperate with billing
logic that must live server-side (ZeroDB backend / AINative dashboard),
plus the open product questions that block any of it from being built.

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

## Open product/business questions (block implementation)

These need a product decision before any more plugin code should be
written against them — guessing at them risks exactly the kind of
invented-billing-logic this design doc exists to avoid:

1. **Plan tiers and limits.** The issue names "$99/mo, 100k credits" but
   doesn't say: is that per team regardless of size, or per-seat? Is there
   a minimum/maximum seat count? Does the free/personal trial tier apply
   per-member inside a team, or does joining a team project override it?
2. **Overage behavior.** "Soft cap with notification to admin" — does the
   plugin need to degrade gracefully (e.g. `/remember --team` starts
   failing, or falls back to personal?) once the team is over quota, or is
   overage purely a backend/billing-side concern invisible to the plugin
   until a hard stop? If the plugin must surface overage state, what API
   does it call to check it, and on what cadence (every team op? session
   start only?)?
3. **Invite flow.** "Admin shares invite link → member connects their
   Claude Code to team project" — today `/memory team setup <team-project-id>`
   requires knowing the raw project ID and having `ZERODB_API_KEY` access
   to it already. Is the intended flow instead: admin generates an invite
   token/link from the dashboard → member runs something like
   `/memory team setup --invite <token>` → the plugin exchanges the token
   for a project ID *and* provisions/attaches the member's API key access
   to that project? That's a materially different (and bigger) piece of
   plugin work than what exists now, and needs a defined invite-token API
   before it can be built.
4. **Admin identity / permissions model.** Nothing in the plugin currently
   knows who is a "team admin" versus a regular member — that distinction
   (if it needs to affect plugin behavior at all, e.g. gating who can run
   `/memory team setup`) has to be defined by the backend's permission
   model first.
5. **Seat accounting.** Does "seat" map 1:1 to a ZeroDB API key / Claude
   Code install, or to an AINative user account that might use the team
   project from multiple machines? This affects whether the plugin needs
   to do anything at all for seat counting (if the backend can infer seats
   from distinct `metadata.author` values or from distinct API keys hitting
   the team `project_id`, the plugin may need zero changes).

## If/when those are answered: likely shape of the plugin-side work

Sketched only so a future implementer has a starting point — none of this
should be built until the questions above are resolved:

- A `/memory team usage` (or similar) subcommand that calls a backend
  endpoint (does not exist yet) returning the team project's credit
  balance/quota, and renders it next to the existing `/memory stats`
  team section already added for #19.
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
  personal project ID.

## Non-goals of this document

- No pricing numbers, seat limits, or overage policy are proposed here —
  those are product/business decisions, not technical ones, and inventing
  them would risk shipping billing behavior nobody signed off on.
- No backend/dashboard implementation is proposed — this plugin repo
  cannot implement billing enforcement itself; it can only cooperate with
  a backend that does.
