# EBU STL

Exports subtitles as EBU STL (`.stl`), the teletext subtitle file broadcasters ask for, as described in EBU Tech 3264.

- **Where.** **EBU STL (EBU STL)** shows in **File › Export as…** and in **Save as**. It exports only; it doesn't open `.stl` files.
- **Subtitles.** Each Dialogue Line with a duration becomes one subtitle, in time order. Comments, empty Lines and drawings are left out. `\N` starts a new row, and rows longer than 40 characters wrap at a space.
- **Rows.** A subtitle holds at most 2 rows of 40 characters, in double height and boxed, as teletext shows them. A Line with more is cut to its first 2 rows, and the export names it by its row number, so you can find it in the Grid.
- **Formatting.** `\i` and `\u` (and the Style's italic and underline) become teletext italic and underline. Colours, fonts and sizes are dropped.
- **Placement.** `\an7`–`\an9` (or a top-aligned Style) put the subtitle at the top of the screen; everything else goes at the bottom. The alignment's column sets left, centred or right justification.
- **Characters.** Text is written in the Latin character table, which covers Western, Central and Northern European letters. A character it lacks becomes `?`, and the export names the Line.
- **Time.** Times are timecodes at 30 frames a second when the frame rate is nearer 30 (29.97, 30, 59.94, 60), and 25 otherwise. The frame rate is Export's, else the video's, else 25.

## The file header

| Field | Value |
| --- | --- |
| Code page | 850 |
| Disk format | `STL25.01` or `STL30.01` |
| Display standard | Level-1 teletext |
| Character table | 00, Latin |
| Language | From Script Info `Language` (`en`, `de_DE`, `French`…), else 00, unknown |
| Programme title | Script Info `Title`, else the file's title |
| Translator | Script Info `Translation` |
| Editor | Script Info `Original Editing` |
| Created, revised | The day of the export |
| Rows, characters | 23 rows, 40 characters |
| Start of programme | 00:00:00:00 |
