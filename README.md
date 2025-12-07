# TinyLLM

A lightweight macOS application for running small language models locally on Apple Silicon Macs. Designed for efficient LLM inference on standard hardware, particularly optimized for M3 Macs with 16GB RAM.

## Features

- **Local LLM Server**: Run quantized GGUF models via llama.cpp
- **Memory-Aware**: Automatic configuration based on available RAM and hardware
- **Apple Silicon Optimized**: Leverages Metal acceleration for M1/M2/M3/M4 chips
- **Smart Safeguards**: Memory pressure detection, thermal monitoring, and auto-throttling
- **Model Management**: Download, benchmark, and switch between models
- **OpenAI-Compatible API**: Standard `/v1/completions` endpoint for easy integration

## Requirements

- macOS 14.0 or later
- Apple Silicon Mac (M1, M2, M3, or M4) or Intel Mac
- 8GB RAM minimum (16GB recommended for 7B models)
- Command-line tools (Xcode Command Line Tools)

## Quick Start

### Build from Source

```bash
# Clone the repository
cd TinyLLM

# Build using Xcode
xcodebuild -project TinyLLM.xcodeproj \
  -scheme TinyLLM \
  -configuration Release \
  -derivedDataPath build/Release \
  clean build

# Launch the app
open build/Release/Build/Products/Release/TinyLLM.app
```

### First Run

1. **Build llama.cpp**: On first launch, TinyLLM will automatically:
   - Clone the llama.cpp repository
   - Build the llama-server binary with Metal support
   - This takes 2-5 minutes depending on your Mac

2. **Download a Model**: Choose from preset models or add a custom GGUF model:
   - Qwen2.5 Coder 7B (recommended for coding)
   - Mistral 7B v0.3 (general purpose)
   - Phi-3 Mini (lightweight, 4K context)
   - DeepSeek-R1 8B (reasoning)

3. **Start the Server**: Click "Start" to launch the LLM server
   - Default endpoint: `http://127.0.0.1:8000/v1`
   - Monitor CPU, memory, and thermal state in real-time

## Usage

### Basic Configuration

TinyLLM automatically configures optimal settings based on your hardware:

- **16GB RAM**: 32K context, 512 batch size, full GPU offload for 7B models
- **8GB RAM**: 8K-16K context, 256 batch size, partial GPU offload
- **M3/M4 Chips**: Flash Attention enabled for better performance

### Profiles

Switch between inference profiles for different use cases:

- **Coding**: Lower temperature (0.15), precise and deterministic
- **Creative**: Higher temperature (0.85), diverse outputs
- **Strict**: Very low temperature (0.05), minimal hallucination
- **Balanced**: Middle ground (0.35), general conversation

### Advanced Settings

Access advanced options in the Settings window:

- **Context Size**: Override automatic context planning
- **GPU Layers**: Control Metal offloading (999 = all layers)
- **KV Cache Quantization**: q4_0, q4_1, or q5_0
- **Flash Attention**: Enable on M2+ for better long-context performance
- **RoPE Scaling**: Extend context beyond model's training length
- **Extra Arguments**: Pass raw llama-server flags

### Memory Safeguards

Enable automatic memory management:

- **Auto-Throttle Memory**: Stop server on high memory pressure
- **Auto-Reduce Runtime**: Decrease context/batch under pressure
- **Auto-Switch Quant**: Fall back to lighter quantization variant

### API Usage

Use the OpenAI-compatible endpoint with any client:

```bash
curl http://127.0.0.1:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf",
    "prompt": "Write a Python function to calculate fibonacci numbers",
    "max_tokens": 256,
    "temperature": 0.15
  }'
```

Or use with Python:

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:8000/v1",
    api_key="not-needed"
)

response = client.completions.create(
    model="Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf",
    prompt="Explain async/await in Swift",
    max_tokens=512,
    temperature=0.15
)

print(response.choices[0].text)
```

## Model Recommendations

### For M3 16GB RAM

| Model | Size | Context | Use Case | Memory |
|-------|------|---------|----------|--------|
| Qwen2.5 Coder 7B Q4_K_M | 4.4GB | 32K-128K | Code generation | ~7-9GB |
| Mistral 7B Q4_K_M | 4.1GB | 32K | General text | ~7-8GB |
| Phi-3 Mini Q4 | 2.2GB | 4K | Lightweight tasks | ~4-5GB |
| DeepSeek-R1 8B Q4_K_M | 4.9GB | 32K | Reasoning | ~8-10GB |

### Quantization Guide

- **Q4_K_M**: Best balance of quality/size (recommended)
- **Q5_K_M**: Slightly better quality, +20% size
- **Q6_K**: Near-full precision, +50% size
- **Q4_0/Q4_1**: Smallest, faster but lower quality

## Architecture

TinyLLM is built with Swift 6 and leverages modern concurrency:

- **LLMManager**: Core orchestrator with `@MainActor` for UI updates
- **ProcessService**: Actor-based process management for llama-server
- **HardwareService**: System detection and monitoring
- **ModelIndexService**: Metadata tracking and benchmark storage
- **Memory Safeguards**: Runtime adaptation to system pressure

### Key Components

```
Sources/TinyLLM/
├── LLMManager.swift           # Main controller
├── ProcessService.swift       # Process lifecycle
├── HardwareService.swift      # System detection
├── ThermalService.swift       # Thermal monitoring
├── ModelIndexService.swift    # Model metadata
├── BenchmarkService.swift     # Performance testing
├── MainWindowView.swift       # Primary UI
├── ModelManagerView.swift     # Model library
└── AdvancedSettingsView.swift # Configuration
```

## Performance Tips

### Maximize Throughput

1. **Use full GPU offload** (`nGpu = 999`) on Apple Silicon
2. **Enable Flash Attention** on M2/M3/M4
3. **Increase batch size** to 1024 on 32GB+ systems
4. **Use Q4_K_M quantization** for best speed/quality

### Minimize Memory Usage

1. **Reduce context size** (16K or less for 8GB RAM)
2. **Lower KV cache quantization** (q4_0)
3. **Enable auto-reduce safeguards**
4. **Use smaller models** (Phi-3 Mini, 3B models)

### Long-Running Stability

1. **Monitor thermal state** - reduce load if hitting "heavy" or "hotspot"
2. **Watch memory percentage** - stay below 75% for headroom
3. **Enable debug mode** for detailed diagnostics
4. **Restart server periodically** if using very long conversations

## Troubleshooting

### Server Won't Start

- Ensure llama.cpp is built: Check for `llama.cpp/build/bin/llama-server`
- Rebuild: Click "Rebuild llama.cpp" in Build Panel
- Check logs for CMake errors

### Out of Memory Crashes

- Reduce context size to 16K or 8K
- Use lighter quantization (Q4_0 instead of Q5_0 for KV cache)
- Enable "Auto-Reduce Runtime on Pressure"
- Switch to smaller model (3B instead of 7B)

### Slow Inference

- Verify GPU offload: Check `nGpu` is set to 999
- Enable Flash Attention if on M2+
- Reduce context if unnecessarily large
- Check thermal state - system may be throttling

### High Memory After Running

- Log files can grow large - they're stored in `~/Library/Application Support/TinyLLM/`
- Manually clear old logs if needed
- Restart the app to reset memory baseline

## Development

### Building

Requires Swift 6.0 and macOS 14 SDK:

```bash
swift build -c release
```

### Contributing

This is currently a personal project, but contributions are welcome:

1. Focus on memory efficiency and Apple Silicon optimization
2. Follow existing patterns (actors for services, @MainActor for UI)
3. Test on constrained systems (16GB RAM minimum)
4. Maintain zero external dependencies where possible

### Known Issues

See `tasks.md` for tracked improvements:

- Memory optimizations in progress (log tail reading, task lifecycle)
- Dynamic context sizing based on available memory (planned)
- Thermal-aware throttling (planned)

## License

[Your chosen license here]

## Credits

- Built on [llama.cpp](https://github.com/ggerganov/llama.cpp) by Georgi Gerganov
- Designed for efficient local LLM inference on consumer hardware
- Optimized for Apple Silicon with Metal acceleration

## FAQ

**Q: Can I use this with Ollama models?**
A: TinyLLM uses raw GGUF files. You can use models from Hugging Face or convert Ollama models to GGUF.

**Q: Does this work on Intel Macs?**
A: Yes, but performance will be significantly lower without Metal acceleration. GPU offload won't be as effective.

**Q: How much VRAM do I need?**
A: Apple Silicon uses unified memory. The RAM estimates include both system and GPU memory.

**Q: Can I run multiple models simultaneously?**
A: Not currently - TinyLLM manages one llama-server instance at a time.

**Q: What's the maximum context size?**
A: Limited by RAM. On 16GB, 32K is safe for 7B models. 64K+ requires 32GB+ or aggressive quantization.

**Q: Is this production-ready?**
A: TinyLLM is designed for local development and experimentation. For production, consider managed solutions or containerized llama.cpp deployments.

---

**Status Bar Icon**: Look for the brain icon in your menu bar for quick access while the app is running.



$ /bin/zsh -lc 'xcodebuild -project TinyLLM.xcodeproj -scheme TinyLLM -configuration Release -derivedDataPath build/Release clean build'

open /Users/andrzejmarczewski/Documents/GitHub/tinyllm/TinyLLM/build/DerivedData/Build/Products/Release/TinyLLM.app