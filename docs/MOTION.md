# Motion design

Built on Claude commit `8e4e748bf12a805c18d523f3c5840fb3846613d0`, on `codex/premium-motion`.

The goal is a calm, responsive macOS utility: content should stay anchored while switching projects, and motion should explain an action without delaying it. No animation waits before a model mutation or file operation.

| Interaction | Motion |
|---|---|
| Workspace switch | Old and new cards crossfade, with a directional 24-point handoff over 280 ms. Only one outgoing collection is retained; repeated switches cancel old cleanup. |
| Adaptive panel | Native window frame animation follows changed content width over the same 280 ms; no resize animation starts during a drag. |
| Open / close | Panel fade, shorter rope reveal and a restrained capped card stagger; reopening invalidates stale close completions. |
| Add / remove / reorder | Softer damped springs and shorter travel; existing intentional removal feedback remains. |
| Search / group collapse | Filtered cards fade, remaining cards ease into position. Group labels travel with their cards. |
| Card selection / hover | Selection outline fades; shadows interpolate without changing card geometry. Hit-testing follows presentation-layer positions. |
| Toolbar | Existing interruptible hover slide/fade is retained; contextual actions animate and the bar fades with dismissal. Pin, Settings and EXIT remain fixed. |
| Theme / feedback | Theme dissolves, status messages fade in and out. Initial status is invisible. |
| Workflow windows | Native window behavior plus a short fade/content reveal, preserving focus and window geometry. Native save/open/share/Quick Look controls retain macOS behavior. |
| Collection / onboarding / editor / export / rules / history | Scoped SwiftUI animations for selection, layout, step changes, conditional tools, progress/result controls and list updates. Editing gestures are not wrapped in delayed animation. |

Reduce Motion uses short fades and removes workspace travel. SwiftUI observes accessibility changes; changing accessibility settings also stops in-flight workspace motion and ambient sway. Transient Core Animation layers are removed after completion or hide. There is no animation polling timer; movement runs on the render server.

Validation: seven new motion regressions cover workspace interruption, hiding during a switch, selection/hover geometry, window presentation, reduced-motion parameters, status expiry and rapid close/reopen. Full local suite: 149 tests, zero failures. Xcode Debug build and standalone release build succeed; app self-test: 28 checks. Native visual checks and installation are recorded in docs/TESTING.md.
