# OpenPlanner Evals

Tests for the core planning agent (`core/openplanner`).

## Suites

| Suite | File | What it checks |
|-------|------|----------------|
| smoke | `tests/smoke-test.yaml` | Conversational path: introduces itself, no approval needed |
| grounding | `tests/plan-grounding.yaml` | Task path: ContextScout first, verified paths, approval-gated draft, zero source writes |

## Run

```bash
cd evals/framework
npm run eval:sdk -- --agent=openplanner --suite=smoke-test
npm run eval:sdk -- --agent=openplanner --suite=plan-grounding
```
