# Feature specifications

This directory is the source of truth for product scope. Each specification has
one stable identifier, an explicit status, acceptance criteria and known
non-goals. Implementation, tests and release notes should reference that ID.

Start a new specification from [TEMPLATE.md](TEMPLATE.md). The YAML frontmatter
is mandatory and machine-readable. Keep applicable template headings in order;
for a genuinely inapplicable section, write `Not applicable — <reason>`.

## Statuses

- **implemented** — present in the library and covered by automated tests.
- **partial** — public surface exists but one or more required behaviours are absent.
- **planned** — accepted scope; no production implementation yet.
- **decision-required** — implementation is blocked by a product or legal choice.

## Domains

| Domain | Focus |
| --- | --- |
| [data](data) | Ingestion, contracts and provider adapters |
| [platform](platform) | HTTP, configuration, rate limits, caching and telemetry |
| [research](research) | Indicators and data-analysis primitives |
| [strategy](strategy) | Signals, simulation, performance and optimisation |
| [quality](quality) | Tests, compatibility and delivery confidence |
| [product](product) | Licensing and distribution policy |

## Rules

1. Add a specification before changing a feature with user-visible behaviour.
2. Do not mark a feature `implemented` until all its acceptance criteria are automated.
3. A provider capability is never inferred from another provider; it must be
   recorded in its own adapter specification.
4. Use `<DOMAIN>-<NNN>-<kebab-case-name>.md`; identifiers are never reused.
