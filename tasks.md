# 🧩 TinyLLM Full Task List  
Comprehensive issue list extracted from the full code review.

---

## 🔴 CRITICAL ISSUES

### 1. **Major Memory Leak – ProcessService.swift (Lines 68–78)**
- [x] Detached task reading from pipe never terminates  
- [x] Holds file handle references after process dies  
- [x] Background tasks continue indefinitely  
- [x] Memory grows unbounded when restarting server  
- [x] Critical for long-running usage  
**Fix:**
- [x] Store task reference (`logTask`)  
- [x] Cancel and nil out in `terminate()`  

### 2. **File Handle Leaks – LLMManager.swift (Lines 813–818)**
- [x] `try? handle.close()` swallows failures  
- [x] If close fails, descriptor leaks  
- [x] Happens on every log write  
**Fix:**
- [x] Wrap in `do/catch` with `defer { try? close }`  

### 3. **Inefficient Log Tail Reading – LLMManager.swift (835–838)**
- [x] Reads entire log file into memory each update  
- [x] For long runs, file becomes huge  
- [x] Called on every FS event  
- [x] High RAM usage on M3 16GB  
**Fix:**
- [x] Replace with “read last N bytes” tail logic  

### 4. **Timer Retention Cycle Risk – LLMManager.swift (610–612)**
- [x] Timer → Task pattern creates nested async contexts  
- [x] Multiple repeating timers (health + metrics)  
- [x] Possible runaway task creation  
**Fix:**
- [x] Replace timers with async-loop tasks  
- [x] Add proper cancellation (`healthTask`)  

---

## ⚠️ SIGNIFICANT INEFFICIENCIES

### 5. **Redundant Hardware Detection – HardwareService.swift**
- [x] `detectRAM()` called every 3s  
- [x] Syscall performed every time  
- [x] Unnecessary overhead  
**Fix:**
- [x] Add RAM cache (`cachedRAMGB`)  

### 6. **Excessive UserDefaults Writes – LLMManager.swift (71–95)**
- [x] Every `@Published` change triggers disk write  
- [x] `applyRecommended()` writes 8+ values one by one  
- [x] Guard during restore helps but still heavy  
**Fix:**
- [x] Batch writes into one dictionary commit  

### 7. **Code Duplication – Log Viewer**
- [ ] Same ScrollView/Text UI duplicated in:  
  - LogsPaneView.swift:21–29  
  - MainWindowView.swift:217–227  
**Fix:**
- [ ] Create reusable `LogViewerComponent`  

### 8. **Formatters Created Per View Instance – ModelManagerView.swift**
- [ ] New formatters for each row  
- [ ] Expensive initialization  
**Fix:**
- [ ] Make static/shared singleton formatters  

### 9. **Inefficient Model Index Persistence – ModelIndexService.swift (138–146)**
- [x] Pretty printing and sorted keys slow  
- [x] Called on every scan  
- [x] async queue + mutable dict + @unchecked Sendable = risk  
**Fix:**
- [x] Remove pretty printing  
- [x] Debounce updates  
- [x] Consider converting to an actor  

---

## 🟡 LLM-SPECIFIC OPTIMIZATIONS (M3 / 16GB)

### 10. **Context Size Too Conservative**
- [ ] Caps at 32K for 16GB  
- [ ] Doesn’t account for M3 UM architecture  
- [ ] No dynamic memory check  
**Fix:**
- [ ] Safe increase to 48K–64K for 7B  
- [ ] Base on available memory, not total RAM  

### 11. **No KV Cache Size Limits**
- [ ] Cache can grow unbounded  
- [ ] Critical for long conversations  
**Fix:**
- [ ] Add explicit `--cache-size` argument  

### 12. **Missing Memory-Aware Batch Size**
- [ ] Always 512, even under pressure  
**Fix:**
- [ ] Compute adaptive batch size based on memory state  

### 13. **Thermal Monitoring Is Passive**
- [ ] Detects thermal state but doesn’t react  
- [ ] On M3, GPU throttling hurts inference  
**Fix:**
- [ ] Reduce GPU layers and batch size under heat  

---

## 📦 LIBRARY USAGE ANALYSIS

### Current Dependencies
- Zero external dependencies (good)  

### Optional Enhancements
- [ ] Add SwiftLog for structured logging  
- [ ] Add SwiftSystem for safer file ops  
- [ ] Add AsyncAlgorithms for async timers  

---

## 🔧 QUICK WINS (Prioritized for M3 / 16GB)

### Priority 1 – Memory (Fix ASAP)
- [ ] Fix log task leak (Issue #1)  
- [ ] Switch log tail to “last N bytes” (Issue #3)  
- [ ] Fix FileHandle leaks (Issue #2)  

### Priority 2 – Performance
- [ ] Cache RAM detection (Issue #5)  
- [ ] Use static formatters (Issue #8)  
- [ ] Add KV cache size limits (Issue #11)  

### Priority 3 – Code Quality
- [ ] Shared LogViewer (Issue #7)  
- [ ] Batch UserDefaults writes (Issue #6)  
- [ ] Replace timers with async loop (Issue #4)  

---

## 📊 ESTIMATED MEMORY IMPROVEMENT

### Current
- Base app: 50–100MB  
- Model 7B Q4: ~4–5GB  
- 32K context: ~2–3GB  
- KV cache: ~1–2GB  
- Logs: 10–500MB  
- **Total: 8–11GB**

### After Fixes
- Log tail fix: save 50–200MB  
- Task leaks: save 20–100MB  
- **Total: 100–300MB saved**  

---

## 🎯 M3 16GB Recommended Defaults

- ctx: **49152**  
- batch: **512**  
- nGpu: **999**  
- cacheK/V: **q4_0**  
- flash: **true**  
- Add dynamic headroom detection  
- Add adaptive throttling  

---




