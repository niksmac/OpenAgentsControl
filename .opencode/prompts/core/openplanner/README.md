# OpenPlanner Prompt Variants

**Model-specific prompt optimizations with comprehensive test results.**

The default prompt is `.opencode/agent/core/openplanner.md` (model-agnostic,
XML-structured, following `docs/agents/research-backed-prompt-design.md`).
Copy `.opencode/prompts/core/openagent/TEMPLATE.md` to add a model-specific
variant here when testing shows the default underperforms on a model family.

---

## 🚀 Quick Start

```bash
# Test the default prompt with eval framework
cd evals/framework
npm run eval:sdk -- --agent=openplanner --suite=smoke-test

# Run full planning suite
npm run eval:sdk -- --agent=openplanner --suite=core-tests

# View results
open ../results/index.html
```

---

## 📊 Capabilities Matrix

| Variant | Model Family | Approval Gate | Context Loading | No-Implementation | Plan Grounding | Pass Rate | Status |
|---------|--------------|---------------|-----------------|-------------------|----------------|-----------|--------|
| `default` | All (agent file) | ✅ | ✅ | ✅ | ✅ | - | 🚧 Needs Testing |

**Legend:**
- ✅ Works reliably (passes tests)
- ⚠️ Partial/inconsistent
- ❌ Does not work
- `-` Not tested yet

**Last Updated:** 2026-09-11
**Test Suite:** Core tests (planned)
**Status:** 🚧 Needs Testing — new agent, awaiting first eval run

---

## 📝 Available Variants

### `default` - Model-Agnostic (Agent File)

**Target Models:** All (structured XML prompt works across Claude, GPT, Gemini, Grok, Llama)

**Optimizations:**
- Intake stage separated from discovery so heterogeneous inputs (spec/screenshot/instructions/bugfix) are normalized before repo reads
- Draft-before-finalize gate: lightweight proposal approved before any `.tmp/plans/` files are written (mirrors OpenCoder Stages 1-3)
- `no_implementation` hard constraint: planner may only write under `.tmp/plans/`
- Plan template with mandatory sections (N/A explicit, never silently omitted)

**Test Results:**
```
Not tested yet — run evals/agents/core/openplanner/tests/ to populate.
```

**Known Issues:** None yet

**Use When:** Default for all models until a variant proves better on evals.
