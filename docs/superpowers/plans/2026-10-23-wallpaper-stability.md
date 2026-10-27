# Wallpaper stability implementation plan

Goal: prevent transient startup failures from permanently disabling wallpaper recovery.

Architecture: retain the existing MIT Codex Dream Skin engine, renderer repair and verified CDP discovery. Separate durable recovery intent from transient state.json. Hidden plain launches remain pending with live services rather than rolling back. Explicit apply still requires visible render verification. Never silently restart an active ordinary Codex session.

User clarification: future reliability is the priority; immediate recovery is not requested. Implementation proceeds inline in current/, whose files are untracked in the historical root repository; do not create a worktree from the obsolete committed baseline. Preserve pre-edit files in local evidence. No installation or publication.

Plan / acceptance:
- Add executable regression tests for hidden pending classification and durable recovery after session loss; first confirm failure.
- Update common state helpers, startup and supervisor: save recovery intent on successful/pending launches, discover current endpoints again, continue recovery with missing session metadata, expose connection-required state. Explicit restore clears intent under the existing operation lock.
- Preserve identity checks, pause semantics and strict apply verification. No hidden page is reported as rendered.
- Run Node suite and relevant Windows startup/restore/monitor suites. Record results and remaining native integration limits.

Review focus: stale PID/port reuse; cancel/restore racing recovery; hidden vs invalid renderer; video service recovery after session loss; ordinary non-CDP launch.

Limits: CDP cannot be added to an already running ordinary instance. Supporting every launch entry without interruption requires an approved launch integration or native app support. Startup/reboot and Windows upgrade behavior require real installation testing; unit tests do not establish these outcomes.
