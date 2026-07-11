---
id: <DOMAIN>-<NNN>
status: planned # planned | partial | implemented | decision-required
domain: <data | platform | research | strategy | quality | product>
owners: [<module-or-team>]
depends_on: []
---

# <ID> — <Feature name>

## Goal

<One short paragraph describing the user or system outcome.>

## Scope

- <Included behaviour 1>
- <Included behaviour 2>
- <Included behaviour 3>

## Requirements

- <Observable functional requirement>
- <Data, security, performance, or reliability requirement>
- <Error-handling requirement>

## API and data contract

<Public functions, options, return values, schemas, units, nullability and
backwards-compatibility impact. Write `not applicable` only when there is no
public contract.>

## Acceptance criteria

- [ ] <Automated test proving the main success path>
- [ ] <Automated test proving an error or boundary path>
- [ ] <Documentation/example updated>
- [ ] <Telemetry, security, performance, or migration criterion when relevant>

## Non-goals

- <Explicitly excluded behaviour>
- <Deferred adjacent work>

## Risks and open decisions

- <Risk, assumption, provider limitation, or decision owner>

## Test strategy

<Unit, fixture/contract, integration, property, benchmark, or migration tests.
State why a category is not needed when omitted.>

## Rollout and migration

<Feature flag, configuration, data migration, release-note and rollback plan.
State `none` for internal or backwards-compatible changes.>

## References

- <Related feature specification>
- <Relevant module, existing documentation, issue, or external provider document>
