# Glossary

Keeps a team's terms consistent. List the terms to avoid, each with the term to use instead, and every use shows up as a problem.

- **Write the glossary.** In Settings › Plugins › Glossary, add one row per term: the term to avoid, then `→` (or `->`) and the term to use, such as `e-mail → email`. A term alone, such as `utilize`, is flagged with no fix. A Project can keep its own glossary.
- **See the uses.** Each use is a row in the Problems list, a squiggle in the line editor and a mark in the Grid. **Show uses as** picks how serious they look: Error, Warning, Information or Hint.
- **Fix them.** Quick fix (Alt+Enter) in the line editor, or a row's menu in the Problems list, puts the preferred term in as one undo step. A capitalised word gets a capitalised replacement, and a word in capitals gets one in capitals.

The plugin checks again whenever a file changes or opens, and on **Check the glossary now**.

## How terms match

- Whole words only: `ok` matches "ok" but not "okay" or "token".
- Upper and lower case are the same unless **Match case** is on.
- Override tags such as `{\i1}` and the `\N`, `\n` and `\h` escapes are never matched, and they end a word.
- Where two terms overlap, the longer one wins.
- Comment Lines are skipped.

## Needs

No permissions. The plugin reads the open files' Lines and sets problems on them; it never changes a Line unless you choose a quick fix.
