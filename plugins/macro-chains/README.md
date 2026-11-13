# Macro chains

Record a chain of HikariSub commands and Automation macros, with the answers you gave their dialogs, and run it again as one undo step.

Inspired by [AegisubChain](https://github.com/arch1t3cht/AegisubChain) by arch1t3cht.

## What it needs

A HikariSub whose plugins can group their steps into one undo step ([altqx/hikari#1116](https://github.com/altqx/hikari/pull/1116)). On an older HikariSub the plugin loads, but its panel and commands only say to update HikariSub; your chains stay as they are.

## Record a chain

Open the **Macro chains** panel (View › Panels) and choose **Record a chain**, or run the *Record a chain* command. Then work as usual: each macro and command that applies becomes a step, with what you answered in its dialogs. Undo while recording takes the last step back, and Redo brings it back. Name the chain and choose **Stop and save**.

## Edit a chain

Choose a chain and **Edit**. For each step you can:

- choose the **selection after this step**: the macro's own selection, the selection from before the step, or the lines the step changed;
- show the step's dialogs, filled in, every time it runs;
- set each dialog field to **Constant** (the recorded value, which you can change here), **Ask** (asked for when the chain runs) or **Exclude** (left as the dialog has it).

Steps move up and down, and can be removed. A chain can take one of five shortcut slots, *Run chain slot 1* to *5*, which you can give keys in Settings › Shortcuts.

## Run a chain

Choose **Run**, or the chain's slot command. Every Ask field of every step is asked in one dialog first. The chain then runs as one undo step. When a step fails, the chain stops there, and **Undo the chain** takes back the steps that ran.

## Import AegisubChain chains

Choose **Import AegisubChain chains…** and pick AegisubChain's configuration file (`arch.AegisubChain.json` in Aegisub's DependencyControl config folder) or a file of exported chains. The panel shows what it found before adding anything. AegisubChain doesn't save the fields it leaves out, so an imported chain shows each of its dialogs once, filled in, the first time it runs, and learns them. After that it runs as recorded. A button AegisubChain left to the user becomes the recorded one, and a step whose macro isn't loaded stays in the chain until its script is.

## Where chains are kept

In `chains.json`, in the plugin's own data folder. The plugin needs no other permission.

## Licence

MIT.
