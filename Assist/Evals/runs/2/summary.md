| Reader | Checks | Correct | Wrong (one tap) | Flagged | Missed | Failed | Model s/msg |
|---|---|---|---|---|---|---|---|
| gemma3-4b | off | 36/52 | 8 | 6 | 2 | 0 | 25.3 |
| gemma3-4b | on | 42/52 | 0 | 8 | 2 | 0 | 25.3 |
| rules + gemma3-4b | off | 36/52 | 8 | 6 | 2 | 0 | 10.5 |
| rules + gemma3-4b | on | 42/52 | 0 | 8 | 2 | 0 | 10.5 |
| llama3.2-3b | off | 32/52 | 11 | 9 | 0 | 0 | 14.5 |
| llama3.2-3b | on | 38/52 | 0 | 14 | 0 | 0 | 14.5 |
| rules + llama3.2-3b | off | 32/52 | 11 | 9 | 0 | 0 | 6.0 |
| rules + llama3.2-3b | on | 38/52 | 0 | 14 | 0 | 0 | 6.0 |
| qwen2.5-3b | off | 33/52 | 10 | 9 | 0 | 1 | 13.4 |
| qwen2.5-3b | on | 39/52 | 0 | 13 | 0 | 1 | 13.4 |
| rules + qwen2.5-3b | off | 33/52 | 10 | 9 | 0 | 1 | 5.6 |
| rules + qwen2.5-3b | on | 39/52 | 0 | 13 | 0 | 1 | 5.6 |
| qwen2.5-7b | off | 31/52 | 11 | 10 | 0 | 0 | 38.1 |
| qwen2.5-7b | on | 39/52 | 0 | 13 | 0 | 0 | 38.1 |
| rules + qwen2.5-7b | off | 31/52 | 11 | 10 | 0 | 0 | 15.6 |
| rules + qwen2.5-7b | on | 39/52 | 0 | 13 | 0 | 0 | 15.6 |
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
