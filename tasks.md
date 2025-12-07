Below is a clean, ready-to-paste, fully formatted Markdown task list, prioritised exactly as discussed.

It is formatted to be a GitHub-friendly project task file, suitable for /docs/tinyllm_task_list.md or a GitHub Project board.


---

🛠️ TinyLLM — High-Impact Priority Task List

Ordered from highest impact → lowest impact (Tier 0 → Tier 3)

Based on full review of all 21 project files


---

🟥 TIER 0 — Immediate, Highest-Impact Improvements

0.1 Unify Metrics & Health (Major Stability Fix)

[x] Create RuntimeMetrics struct with:

[x] systemMemPercent

[x] llmMemPercent

[x] llmCPUPercent

[x] thermalState


[x] Replace 2 async loops with one updateRuntimeState() loop inside LLMManager

[x] Move metrics loop out of AppDelegate

[x] All health logic reads from the unified metrics struct



---

0.2 Add Process-Level Memory Tracking (Prevents Crashes)

[x] Extend ProcessService.getProcessMetrics() to include %mem

[x] Add llmMemPercent to RuntimeMetrics

[x] Update memory pressure classification to use:

[x] System memory

[x] LLM process memory


[x] Update auto-safeguards to use new combined pressure logic



---

0.3 Safer Context & KV Cache Defaults (Essential for 16GB Macs)

[x] Add RAM-sensitive ctxSize ceilings:

[x] 8GB: 8–16k

[x] 16GB: 32–48k

[x] >7B on 16GB: ≤32k

[x] 32GB: 65k–128k


[x] Implement RAM-aware KV cache sizing:

[x] cacheRamMB = min(ramGB * 256, ctx / 4)


[x] Add safe fallback if memory pressure is high during startup



---

0.4 Debounce Log Tail Updates (Big CPU Optimization)

[x] Throttle log tail updates to 150–300ms

[x] Reduce tail bytes from 64KB → 16–32KB

[x] Ensure only one update runs at a time (avoid overlapping work)



---

0.5 Reduce Default GPU Layers (Metal Stability Fix)

[x] Replace default 999 GPU layers with RAM-aware values:

[x] 8GB → 30–60 layers

[x] 16GB → 80–120 layers

[x] 32GB → “all layers” allowed


[x] Apply thermal scaling after this base value

[x] Add “GPU Aggressiveness” setting (Low / Balanced / High / Max)



---

🟧 TIER 1 — High-Value Improvements

1.1 Static ISO8601 Formatter

[x] Replace ISO8601DateFormatter() per log line with:

static let df = ISO8601DateFormatter()



---

1.2 Host Performance Profiles

Add a simple UI dropdown:

[x] Quiet Mode

Low threads

Lower GPU layers

Smaller batch


[x] Balanced (current defaults but safer)

[x] Performance Mode

Max threads

Max GPU layers

Higher batch




---

1.3 Flash Attention Capability Detection

[x] Run one-time check:

llama-server --help | grep flash-attn

[x] Disable toggle if unavailable

[x] Store support flag in hardware detection



---

1.4 Separate Host & Server Logs

[x] Create tinyllm.log (app logs)

[x] Create llama-server.log (server output)

[x] Add UI toggle: Host / Server / Combined

[x] Adjust ProcessService to only write server logs

[x] Adjust LLMManager.appendLog to only write host logs



---

🟨 TIER 2 — Medium-Impact Enhancements

2.1 Emergency Safe Mode

Trigger when:

llmMemPercent > 25–30%

OR systemMemPercent > 80%

OR thermal == .hotspot


Actions:

[ ] Reduce ctx to 4–8k

[ ] Reduce batch by 50–70%

[ ] Reduce GPU layers to < 25%

[ ] Disable FlashAttention

[ ] Lower threadCount

[ ] Show Safe Mode badge in UI



---

2.2 Improved Extra Args Parsing

[ ] Build a mini argument tokenizer (supports quotes)

[ ] Replace .split(" ") in server launch



---

2.3 UI Enhancements

[ ] DiagnosticsOverlay: display LLM mem + system mem

[ ] StatusMenuView: live TPS, ctx, mem, thermal

[ ] Add “Reset to Safe Defaults” button to Advanced Settings



---

🟩 TIER 3 — Future Improvements / Nice-to-Have

3.1 Intelligent Benchmarking

[ ] Benchmark 3 modes per model:

Fast Mode

Balanced

Deep Context


[ ] Store TPS per configuration in ModelIndexService



---

3.2 Auto Model Routing

[ ] Add “Primary Coding Model” selector

[ ] Use coding model when starting server for coding tasks

[ ] Allow a separate “General Chat” model



---

3.3 RoPE Scaling Rules Per Model

[ ] Auto-enable RoPE scaling for models containing “128k” in filename

[ ] Provide warning if user disables scaling on such models



---

✔️ Done — You Now Have a Production-Ready Task List

If you want, I can also:

Convert this into a GitHub Project board

Generate a Kanban swimlane version

Generate a Jira-friendly EPIC + issues

Or format for Notion, Linear, or Xcode TODO comments


Would you like one of those versions?
