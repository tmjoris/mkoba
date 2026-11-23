| Reader | Checks | Correct | Wrong (one tap) | Flagged | Missed | Failed | Median s/msg |
|---|---|---|---|---|---|---|---|
| gemma3-4b | off | 36/52 | 8 | 6 | 2 | 0 | 24.6 |
| gemma3-4b | on | 42/52 | 2 | 6 | 2 | 0 | 24.6 |
| rules + gemma3-4b | off | 36/52 | 8 | 6 | 2 | 0 | 0.0 |
| rules + gemma3-4b | on | 42/52 | 2 | 6 | 2 | 0 | 0.0 |
| llama3.2-3b | off | 31/52 | 12 | 9 | 0 | 0 | 19.3 |
| llama3.2-3b | on | 38/52 | 3 | 11 | 0 | 0 | 19.3 |
| rules + llama3.2-3b | off | 31/52 | 12 | 9 | 0 | 0 | 0.0 |
| rules + llama3.2-3b | on | 38/52 | 3 | 11 | 0 | 0 | 0.0 |
| qwen2.5-3b | off | 33/52 | 11 | 8 | 0 | 1 | 16.6 |
| qwen2.5-3b | on | 19/52 | 1 | 32 | 0 | 1 | 16.6 |
| rules + qwen2.5-3b | off | 33/52 | 11 | 8 | 0 | 1 | 0.0 |
| rules + qwen2.5-3b | on | 36/52 | 1 | 15 | 0 | 1 | 0.0 |
| qwen2.5-7b | off | 30/52 | 11 | 11 | 0 | 1 | 34.0 |
| qwen2.5-7b | on | 38/52 | 3 | 11 | 0 | 1 | 34.0 |
| rules + qwen2.5-7b | off | 31/52 | 11 | 10 | 0 | 0 | 0.0 |
| rules + qwen2.5-7b | on | 39/52 | 3 | 10 | 0 | 0 | 0.0 |
| regex | off | 38/52 | 3 | 1 | 10 | 0 | 0.0 |
| regex | on | 41/52 | 0 | 1 | 10 | 0 | 0.0 |

Wrong or missed with checks on:

- gemma3-4b: note-05 (missed), skip-05 (wrong), note-03 (missed), skip-02 (wrong)
- rules + gemma3-4b: note-05 (missed), skip-05 (wrong), note-03 (missed), skip-02 (wrong)
- llama3.2-3b: skip-01 (wrong), skip-05 (wrong), skip-02 (wrong)
- rules + llama3.2-3b: skip-01 (wrong), skip-05 (wrong), skip-02 (wrong)
- qwen2.5-3b: skip-07 (wrong)
- rules + qwen2.5-3b: skip-07 (wrong)
- qwen2.5-7b: skip-01 (wrong), skip-05 (wrong), skip-02 (wrong)
- rules + qwen2.5-7b: skip-01 (wrong), skip-05 (wrong), skip-02 (wrong)
- regex: note-01 (missed), note-02 (missed), note-03 (missed), note-04 (missed), note-05 (missed), mangled-01 (missed), mangled-04 (missed), swahili-01 (missed), swahili-02 (missed), swahili-03 (missed)
