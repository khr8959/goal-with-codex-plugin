# X Launch Kit

## One-Liner

Claude Code `/goal` is great, but Claude does not need to spend every iteration doing implementation work. goal-dual is a plugin skill you can call from that loop to delegate one implementation step to Codex and return a tiny evidence packet.

## Post Draft

Built a tiny Claude Code plugin:

**goal-dual**

It does one thing:

Claude `/goal` owns the loop.
Codex handles one implementation step.
goal-dual writes compact evidence.
Claude decides next.

No long agent chat.
No auto commits.
No dynamic workflow sprawl.

Just:

`/goal-dual:run <goal>`

then Claude reads:

`.goal-dual/state/evidence-latest.json`

The goal is simple:

use Codex for code work,
keep Claude responsible for judgment,
and keep the context footprint small.

## Japanese Draft

Claude Code の `/goal` は便利だけど、毎回 Claude にコード調査・実装・テストログ読解までさせるとコンテキスト消費が重い。

そこで goal-dual を作った。

やることは1つだけ。

Claude `/goal` が進行管理。
Codex が実装を1ステップ担当。
goal-dual が短い evidence を生成。
Claude が次を判断。

長いAI同士の会話なし。
自動commitなし。
dynamic workflow は別プラグイン。

`/goal-dual:run <ゴール>`

で、Claude が読むのはこれだけ:

`.goal-dual/state/evidence-latest.json`

Codex に実装を任せる。
でも責任と判断は手放さない。

## Demo Script

1. Open a small disposable repo.
2. Run `/goal-dual:doctor`.
3. Run `/goal-dual:run Fix the failing validation test without changing the public API.`
4. Open `/goal-dual:status`.
5. Show `.goal-dual/state/evidence-latest.json`.
6. Explain that Claude can now complete, continue, or stop based on the evidence.

## Do Not Say

- "It replaces Claude /goal."
- "It supports dynamic workflows."
- "It runs a swarm."
- "It pushes PRs automatically."
- "No review needed."
