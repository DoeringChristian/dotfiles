# Independent review

Before handing off substantive work, use the shared `inter-agent-review` skill at
`~/.agents/skills/inter-agent-review/SKILL.md`: Claude obtains a Codex review and
Codex obtains a Claude review. Address valid findings and disclose review failures.
This authorizes the review delegation; it does not authorize unrelated actions.
If `INTER_AGENT_REVIEW=1` or the task says `REVIEWER_ONLY`, review directly without
delegating again. The user's explicit task instructions take precedence.
