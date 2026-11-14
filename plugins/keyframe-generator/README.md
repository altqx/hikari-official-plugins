# Keyframe generator

Finds the scene changes in the open video and makes keyframes from them, as a background job you can cancel. Set them as the video's keyframes, or save them as an Aegisub keyframes file.

## Needs

- HikariSub 0.1.0-beta.4 or later, where a panel button can start a background job ([#1117](https://github.com/altqx/hikari/issues/1117)) and video frames come fast enough to scan a whole episode in minutes ([#1136](https://github.com/altqx/hikari/issues/1136)).
- An open video. The plugin asks for no permissions.
