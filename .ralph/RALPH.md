### **What is Ralph?**

Ralph is a Bun script that runs an `opencode run` loop with a prompt and a PRD, stopping when the agent returns `<promise>COMPLETE</promise>`.

### **How It Works**

- Agent reads `.ralph/prd.json` and `.ralph/context.md`
- Assigned to a model based on `complexity` (`Low` → medium, `Medium`/`High` → xhigh)
- Marks work is completed when output includes `<promise>COMPLETE</promise>`

### **Core Files**

**1. PRD (`.ralph/prd.json`)**

`prd.json` is a JSON array of `PrdItem` entries.

```ts
type PrdItem = {
  title: string;
  description: string;
  complete: boolean;
  priority?: "critical" | "high" | "medium" | "low";
  complexity?: "Low" | "Medium" | "High";
};
```

**2. Prompt (`.ralph/prompt.md`)**

The instruction block passed to `opencode run` each iteration.

**3. Shared Context (`.ralph/context.md`)**

Optional project context the prompt can reference.

**4. Logs (`.ralph/memory.md`, `.ralph/backlog.md`)**

Append-only notes for learnings and issues.

`.ralph/` is gitignored.

```

### **Writing Effective Context and Tasks**

Use these to help an agent start working immediately with minimal back-and-forth.

**Context (`.ralph/context.md`)**

- Start with a 2-4 sentence project overview (what this repo does and who it serves).
- List key paths and what lives there (e.g. `src/api`, `apps/web`, `infra/`).
- Note critical workflows and commands (dev server, tests, build, lint).
- Call out constraints and policies (no network, API keys, coding style rules).
- Include integrations and endpoints with links or file refs if needed.
- Capture current state or known issues only if it affects the task.

**Task descriptions (`.ralph/prd.json`)**

- Make the title specific and action-oriented (e.g. "Add retry to X service").
- Write the description as a checklist of outcomes and constraints.
- Mention the exact files, modules, or feature flags in scope.
- Define success criteria (UI behavior, API output, tests added/updated).
- Note what is out of scope to avoid rabbit holes.

**Example task description**

```json
{
  "title": "Add retries to payment webhook handler",
  "description": "Implement exponential backoff for 5xx responses in `src/server/webhooks/payments.ts`. Cap at 3 retries. Add tests in `src/server/webhooks/__tests__/payments.test.ts` to cover retry behavior. Do not change public API types.",
  "complete": false,
  "priority": "high",
  "complexity": "Medium"
}
```