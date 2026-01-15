Read `.ralph/context.md`
Read the assigned Task and description in `.ralph/prd.json`
Read any other relevant files as necessary to gain additional context

Important:
- Do the ONE task you were given and complete it
- If any `.zig` files were edited, be sure to run `zig build` (or `zig build dvui-lib`) and ensure it compiles before committing your changes.
- When a task is complete, make a single, concise git commit with your changes AND update the task as complete in `.ralph/prd.json`

After commit:
- Note any important details that would be helpful for future work, append clearly and concisely to `.ralph/memory.md` so future contributors can learn from your experience
- Document any potential bugs, high-severity issues, or critical refactorings (ex: monolithic, multi-responsibility files), append concisely to `.ralph/backlog.md`

`.ralph/` is gitignored, so it will not be tracked by git.

When the ENTIRE PRD is complete, output <promise>COMPLETE</promise>