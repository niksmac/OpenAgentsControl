# OpenPlanner - Planning Agent

**Your plan-first partner: repo-grounded implementation plans for features and bugfixes**

---

## Table of Contents

- [What is OpenPlanner?](#what-is-openplanner)
- [When to Use OpenPlanner](#when-to-use-openplanner)
- [When to Use OpenCoder Instead](#when-to-use-opencoder-instead)
- [Inputs](#inputs)
- [Workflow](#workflow)
- [Subagent Delegation](#subagent-delegation)
- [Plan Artifacts](#plan-artifacts)
- [Examples](#examples)
- [Tips for Best Results](#tips-for-best-results)

---

## What is OpenPlanner?

OpenPlanner is a **planning specialist**. It reads your repo, loads your
standards via ContextScout, and produces an implementation plan a competent
engineer (or OpenCoder) can execute without asking clarifying questions.
Plan-first by default: it writes plan artifacts to `.tmp/plans/` freely,
writes elsewhere only when you explicitly ask (harness: `.tmp/plans/**`
allow, everything else ask, secrets/node_modules/.git deny).

**Key Characteristics:**
- 📋 **Plan-first** - defaults to plans; writes elsewhere only on explicit user request
- 🔍 **Repo-grounded** - every file path verified, never invented; unknowns marked ASSUMPTION
- 🖼️ **Multi-input** - spec files, screenshots/mockups, raw instructions, bug reports
- ✅ **Approval-gated** - lightweight draft approved before any plan files are written
- 🤝 **Handoff-ready** - approved plans route straight to OpenCoder for execution

---

## When to Use OpenPlanner

✅ **New features with unclear shape**
- "Here's a spec, plan the implementation"
- "Here's a mockup, what needs to change?"

✅ **Bugfixes that need root-cause analysis first**
- Includes ranked hypotheses, blast radius, and a regression-test step

✅ **Refactors and migrations**
- Approach comparison (options table with verdict) before anyone touches code

✅ **Scoping and sequencing**
- MVP cuts, dependency ordering, parallel-workstream contracts

❌ **Don't use OpenPlanner when:**
- You already know the change and it's 1-2 files → OpenAgent, direct execution
- You want code written now → OpenCoder (or plan-then-build: OpenPlanner → OpenCoder)
- You need domain content, not software plans → copywriter / technical-writer

---

## When to Use OpenCoder Instead

| Situation | Agent |
|-----------|-------|
| "Plan this, I'll review, then build" | OpenPlanner → OpenCoder |
| "Just build it" (clear, approved scope) | OpenCoder |
| "Is this plan sane?" (second opinion on plan.md) | OpenCoder Stage 2 propose, or CodeReviewer |
| General questions, mixed tasks | OpenAgent |

---

## Inputs

| Input | How to give it | What OpenPlanner does |
|-------|----------------|----------------------|
| Spec file | Path or pasted content | Treats as intent, verifies every claimed path/API against the repo, flags contradictions |
| Screenshots / mockups | Attached images | Describes observations before interpreting; never invents routes or component names |
| Instructions | Chat, ticket, issue text | Extracts goal, scope, constraints, acceptance criteria; marks inferences as ASSUMPTIONS |
| Bug report | Repro + expected vs actual + env/logs | Missing repro becomes an explicit ASSUMPTION or a clarifying question |

If critical information is missing, OpenPlanner asks targeted questions
instead of planning around holes (`stop_on_ambiguity`).

---

## Workflow

```
Intake → Discover → Analyze → Draft → (approve) → Finalize → Handoff
```

1. **Intake** - Classify (feature/bugfix/refactor/migration), normalize inputs, align in 3-5 lines.
2. **Discover** - ContextScout finds standards; repo reads verify reality; ExternalScout pins library versions.
3. **Analyze** - Delegate to planning specialists only as needed (architecture, stories, prioritization, contracts).
4. **Draft** - Lightweight proposal (goal, approach, steps, risks, assumptions). **Approval required.**
5. **Finalize** - After approval only: writes `.tmp/plans/{id}/context.md` + `plan.md`.
6. **Handoff** - Points at artifacts, offers direct handoff to OpenCoder with the plan path.

Nothing is written to disk before approval - same discipline as OpenCoder Stages 1-3.

---

## Subagent Delegation

**Discovery (always):** ContextScout · ExternalScout (when external libs/versions matter)

**Planning specialists (as needed):**

| Subagent | When |
|----------|------|
| ArchitectureAnalyzer | Multi-domain feature, unclear module boundaries |
| StoryMapper | Unclear user journey, needs story decomposition |
| PrioritizationEngine | Oversized scope, MVP cut or ordering contested |
| ContractManager | Parallel workstreams needing interface contracts |
| TaskManager | Approved approach needs atomic subtasks (4+ files, >60min) |
| DocWriter | Large or stakeholder-facing plan needing polish |

**Never delegated:** CoderAgent, TestEngineer, BuildAgent, BatchExecutor -
implementation belongs to OpenCoder after handoff.

---

## Plan Artifacts

```
.tmp/plans/{YYYY-MM-DD}-{task-slug}/
├── context.md   # Request, inputs, standards, verified reference files, assumptions
└── plan.md      # Background, goal/non-goals, approach + alternatives,
                 # ordered steps (files + verification + dependencies),
                 # test strategy, risks, rollback, open questions, handoff notes
```

Every `plan.md` section is mandatory (mark N/A explicitly, never silently omit).
Bugfix plans always include a regression-test step.

---

## Examples

```bash
opencode --agent OpenPlanner
> "Plan user authentication from this spec: docs/specs/auth.md"   # Spec → plan
> "This screenshot is the new dashboard — plan the frontend work" # Image → plan
> "Login fails on Safari, here are the logs. Plan the fix."       # Bugfix → plan
> "Plan migrating our API from REST to tRPC"                      # Migration → plan
```

Plan-then-build:

```bash
opencode --agent OpenPlanner
> "Plan the notifications feature, then hand to OpenCoder to build it"
```

---

## Tips for Best Results

1. **Give the raw material** - full spec paths, original screenshots, complete error logs. Planners starve on summaries.
2. **State non-goals early** - "don't touch billing" saves a rejected plan.
3. **Approve the draft, don't rewrite it** - redirect with one correction; OpenPlanner re-grounds from there.
4. **Keep plans executable** - if a step needs mind-reading, send it back. A plan is done when OpenCoder can run it cold.
5. **One plan, one scope** - parallel features get parallel plans, mirroring OpenCoder's one-feature-at-a-time default.
