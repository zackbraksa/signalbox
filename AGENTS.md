# Signalbox

Signalbox is a SwiftPM macOS 14+ system monitor. Preserve local monitoring and the color-only menu bar warning that disappears when the system is healthy. Process label suggestions run on-device on compatible Macs.

## Build and verify

- Build on a Mac with Xcode 26 or later. Run `./script/build_and_run.sh --build` and open `dist/Signalbox.app` to check the affected behavior.
- Run `swift test --disable-sandbox --build-system native` for changes to monitoring logic.
- Preserve Sparkle updates for signed releases.

## Working rules

- Read the repository README and any deeper applicable agent instructions before editing. Verify assumptions against current source.
- Keep changes scoped, preserve unrelated edits, and use project-local tooling and lockfiles.
- Verify the affected behavior before delivery. For substantial changes, use specialist planning, independent review and functional QA. Keep simple work with one agent.
- Prefer the in-app Browser for web QA. Boot simulators on demand and shut down only the devices you booted.
- Use `gh` for GitHub operations and verify the active identity is `zackbraksa`, including the identity used for pushes. External writes and deployments require authorization for the action and target.

## GitHub recommendations

- Never recommend a small or little-known GitHub repository whose legitimacy
  cannot be independently verified. Check maintainer provenance, maintenance and
  release history, real adoption, and working official distribution channels;
  a README, star count, or signed release alone is insufficient. Apply extra
  scrutiny to tools handling secrets, production access, or privileged execution.
