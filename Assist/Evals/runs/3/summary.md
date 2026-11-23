| Reader | Checks | Correct | Wrong (one tap) | Flagged | Missed | Failed | Model s/msg |
|---|---|---|---|---|---|---|---|
| gemma3-4b | off | 36/52 | 7 | 7 | 2 | 0 | 26.0 |
| gemma3-4b | on | 48/52 | 0 | 2 | 2 | 0 | 26.0 |
| rules + gemma3-4b | off | 36/52 | 7 | 7 | 2 | 0 | 11.1 |
| rules + gemma3-4b | on | 48/52 | 0 | 2 | 2 | 0 | 11.1 |
| llama3.2-3b | off | 31/52 | 12 | 9 | 0 | 0 | 20.9 |
| llama3.2-3b | on | 47/52 | 0 | 5 | 0 | 0 | 20.9 |
| rules + llama3.2-3b | off | 31/52 | 12 | 9 | 0 | 0 | 8.9 |
| rules + llama3.2-3b | on | 47/52 | 0 | 5 | 0 | 0 | 8.9 |
| qwen2.5-3b | off | 33/52 | 10 | 9 | 0 | 1 | 16.5 |
| qwen2.5-3b | on | 49/52 | 0 | 3 | 0 | 1 | 16.5 |
| rules + qwen2.5-3b | off | 33/52 | 10 | 9 | 0 | 1 | 7.0 |
| rules + qwen2.5-3b | on | 49/52 | 0 | 3 | 0 | 1 | 7.0 |
| qwen2.5-7b | off | 30/52 | 12 | 10 | 0 | 0 | 43.1 |
| qwen2.5-7b | on | 48/52 | 0 | 4 | 0 | 0 | 43.1 |
| rules + qwen2.5-7b | off | 30/52 | 12 | 10 | 0 | 0 | 17.8 |
| rules + qwen2.5-7b | on | 48/52 | 0 | 4 | 0 | 0 | 17.8 |
| regex | off | 38/52 | 3 | 1 | 10 | 0 | 0.0 |
| regex | on | 41/52 | 0 | 1 | 10 | 0 | 0.0 |

Wrong or missed with checks on:

- gemma3-4b: note-05 (missed), note-03 (missed)
- rules + gemma3-4b: note-05 (missed), note-03 (missed)
- llama3.2-3b: none
- rules + llama3.2-3b: none
- qwen2.5-3b: none
- rules + qwen2.5-3b: none
- qwen2.5-7b: none
- rules + qwen2.5-7b: none
- regex: note-01 (missed), note-02 (missed), note-03 (missed), note-04 (missed), note-05 (missed), mangled-01 (missed), mangled-04 (missed), swahili-01 (missed), swahili-02 (missed), swahili-03 (missed)
