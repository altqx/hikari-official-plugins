# ASS tags

Helps with override tags in the line editor.

- **Fade lengths.** After `\fad(`, the completion list offers a fade to fill in and common lengths such as `200,200`. Typing digits narrows the list.
- **Fonts.** After `\fn`, the list offers the fonts the file's Styles use, narrowed by what you've typed.
- **What a tag does.** Resting the pointer on a tag such as `\fad(200,300)` or `\fscx120` shows what it does with its arguments: "Fade: 200 ms in, 300 ms out", "Width: 120%".

The list opens as you type `(` or `n` inside an override block, or on Ctrl+Space. The built-in tag list still comes first; this plugin's rows follow it.

## Needs

No permissions. The plugin reads the Line you're editing and the file's Styles; it never changes anything you don't pick from the list.
