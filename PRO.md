# schema_reaper Pro — open-core plan

The `schema_reaper` gem stays **MIT, free, and complete for its job**: schema
introspection, the seven analyzers, static + runtime signal, staged migrations,
`table`/`json`/`markdown`/`sarif` output, the CI baseline gate. Everything a
solo developer or single app needs.

**Pro** is a separate paid layer for *teams and multi-database estates* — the
work that only pays off at scale and that individuals rarely need.

---

## Free vs Pro

| Capability | Free (`schema_reaper`) | Pro (`schema_reaper-pro`) |
|---|---|---|
| PostgreSQL adapter | ✅ | ✅ |
| MySQL / MariaDB adapter | — | ✅ |
| 7 core analyzers | ✅ | ✅ |
| Orphan-row + schema-drift analyzers | — | ✅ |
| Runtime attribute tracker | ✅ (file sink) | ✅ + Redis / StatsD / OTLP sinks |
| Reporters | table / json / markdown / sarif | + HTML, Slack, Jira, PR review comments |
| Reclaimable estimate | bytes/row × est. rows | real `pg_total_relation_size`, index bloat, $ per cloud plan |
| History / trend | local JSONL + `trend` | hosted timeline, burndown charts, per-team dashboards |
| Baseline gate | one file | per-branch baselines, ownership routing (CODEOWNERS) |
| Multi-database / shards | one DB per run | fan-out across N databases, divergence report |
| Scheduled scans + alerts | — | ✅ (cron runner, "queue breached", "new dead column in `billing`") |
| Mountable dashboard engine | — | ✅ `mount SchemaReaper::Pro::Engine` |
| SSO, audit log, RBAC | — | ✅ (Enterprise) |
| Support | GitHub issues, best effort | private issues, SLA |

Pro depends on the OSS gem and reuses its analyzer registry — no fork, no
divergence. New analyzers land in Free first unless they are inherently
team-scale.

---

## Delivery & licensing

- **Distribution**: private gem on a Gemfury / GitHub Packages source, installed
  with a license-key-scoped token.

  ```ruby
  source "https://pro.schema-reaper.dev" do
    gem "schema_reaper-pro"
  end
  ```

- **License check**: offline-friendly signed key (Ed25519), 30-day grace if the
  license server is unreachable. No phone-home of schema content — ever.
- **License**: commercial EULA, per-organization. Source-available to
  subscribers (read + patch), not redistributable.
- **Trial**: 21-day full-feature key, no card.

---

## Pricing (draft)

| Tier | Who | Price | Limits |
|---|---|---|---|
| **Solo Pro** | 1 dev, unlimited personal/side projects | $9 / mo ($90 / yr) | 3 databases |
| **Team** | up to 10 devs | $49 / mo ($490 / yr) | 15 databases, Slack/Jira, scheduled scans |
| **Business** | up to 50 devs | $199 / mo | unlimited databases, dashboard engine, priority support |
| **Enterprise** | 50+ / regulated | custom (from ~$12k / yr) | SSO, audit log, RBAC, on-prem license server, SLA |

Free forever for: OSS projects, students, and any single non-commercial
database. Charity/edu 50% off.

---

## Hosted option (later — biggest ceiling)

`schema-reaper.dev` SaaS: point it at a read-replica, get weekly reports, trend
dashboards, PR comments, and alerts with zero gem install. Same tiers, +$X for
the managed runner. Ship the self-hosted Pro gem first; the SaaS is Pro + a
scheduler + a web app.

---

## Rollout order

1. **Now**: Sponsor button, `PRO.md`, "Pro" section in README (waitlist link).
2. **v1.1 (OSS)**: MySQL adapter groundwork, real size math — proves demand,
   some lands free.
3. **Pro 0.1**: private gem = MySQL + Slack reporter + scheduled scans + license
   key. Sell to the first 10 teams at half price for feedback.
4. **Pro 0.2**: dashboard engine, multi-DB fan-out, per-branch baselines.
5. **SaaS beta**: once ~25 paying teams self-host.

---

## Principles

- Free tier never gets *worse* to sell Pro. No crippling, no nag screens.
- Anything a single app genuinely needs stays free.
- Never transmit schema, data, or query text without explicit opt-in.
- Pro features are the ones a 2-person team can't be bothered to build and a
  50-person org will happily expense.
