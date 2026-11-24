# Typos

Finds common misspellings in the line editor, with [typos-lsp](https://github.com/tekumara/typos-lsp).

- **What it marks.** Misspellings that typos knows, such as "teh" or "recieve", in each open file's text and translation. Each one shows in the Problems panel and as a wavy underline under the word.
- **The fix.** The correction is the problem's quick fix: pick it from the problem's menu, or press Alt+Enter in the line editor. Each fix is one undo step.
- **Tags.** Override tags, `\N`, `\n` and `\h` are left out of the check, so a tag name is never marked and a fix never changes a tag.
- **Comments.** Comment Lines aren't checked.

typos looks for known misspellings, not for every word a dictionary lacks, so it marks few words that are right. It knows English best.

## Needs

- **Runs a program.** HikariSub downloads typos-lsp 0.1.58 for your computer from its GitHub release when you install the plugin, checks it against the hash in the manifest, and runs it in HikariSub's sandbox.
- **No internet when it runs.** typos-lsp gets no network access; your subtitles never leave your computer.

typos-lsp is by Oliver Mannion and others, under the MIT or Apache 2.0 licence.
