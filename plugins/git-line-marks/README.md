# Git line marks

Shows what changed in a subtitle file since a git branch, tag or commit, right in the Grid.

- **Pick a ref.** The Git line marks panel lists the repository's branches (the current one first), its tags and its 50 most recent commits. Search by name, summary or short hash, or type any revision, such as `HEAD~2`, and press Enter.
- **See the marks.** Each Line added since then gets a green mark. A changed, moved or retimed Line gets an amber mark. A red mark on a Line means Lines were removed just above it, or below it on the last Line. Hovering a mark names the change, for example "Changed since v1.0: time, style". The panel lists every marked Line too; double-click one to select it in the Grid.
- **Refresh.** The marks refresh after each save while **Refresh when I save** is on, and whenever you choose Refresh. **Clear marks** removes them. They are never written into the file and go when the plugin stops.

Automation › Git line marks has **Refresh git line marks** and **Clear git line marks**, which you can give shortcuts in Settings › Shortcuts.

## How Lines are matched

The plugin compares ASS Events, not text lines:

1. Lines equal in every field, in the same order, are unchanged.
2. The same Line somewhere else has **moved**.
3. A Line with the same text, but another time, Style, actor, layer, margins, effect or Comment state, has **changed**, and the tooltip names those fields.
4. Between two unchanged Lines, a Line with the same start, end and Style, or with text at least half alike, or the only Line on each side, has **changed**.
5. A text found far away pairs only when it appears once on each side, so a repeated "Yes." isn't taken for a move.
6. What is left was **added**, or **removed**.

## Needs

- HikariSub 0.1.0-beta.4 or later, which has the `document.saved` event ([#1114](https://github.com/altqx/hikari/issues/1114)), and git on PATH (Git for Windows on Windows).
- An ASS file saved in a git repository. Other formats have no Events to match.
- The **Read git** permission (`vcs.read`): the plugin reads the repository's branches, tags and recent commits, and the file as a ref has it. It never changes the repository, and it runs no git of its own: HikariSub runs git read-only.

If git refuses a repository another user owns, the panel shows the `git config --global --add safe.directory` command to run.
