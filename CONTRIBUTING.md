# Contributing to Ram-Otimizador

Thanks for helping optimize RAM for gamers everywhere! 🎮

## 🎯 Good First Issues

### 🌐 **English Translation**
The entire project is in Portuguese. Help us reach English-speaking gamers!

- [ ] Translate README.md
- [ ] Translate menu strings in scripts
- [ ] Create `i18n.json` config
- [ ] Translate docs/
**Effort:** 4-5 hours | **Skill:** Portuguese→English translation

### 🎮 **Add More Games to Detection**
Expand the game detection list.

- [ ] Add: Valorant, Counter-Strike 2, Helldivers 2, Starfield
- [ ] Test detection on real gaming PC
- [ ] Add to `GameDetection.json`
**Effort:** 2 hours | **Skill:** PowerShell + JSON

### 🎨 **GUI Rewrite (Modern UI)**
Replace text menu with modern interface.

- [ ] Research: WPF vs. WinUI vs. Electron
- [ ] Prototype settings UI
- [ ] Maintain feature parity
**Effort:** 10-15 hours | **Skill:** C# or JavaScript

### 📱 **Discord Webhook Notifications**
Alert user via Discord when limpeza happens.

- [ ] Add Discord webhook config
- [ ] Send notification: "RAM Cleaned: 10GB freed"
- [ ] Optional: game-specific alerts
**Effort:** 2 hours | **Skill:** PowerShell + API calls

### 🍎 **macOS Port**
Bring Ram-Otimizador to Mac gamers.

- [ ] Research: Swift + memory management APIs
- [ ] Detect: Game processes on macOS
- [ ] Maintain feature parity
**Effort:** 15+ hours | **Skill:** Swift or Python

### 📊 **Benchmark Script**
Automatize performance testing.

- [ ] Create test scenario (load game, measure FPS)
- [ ] Generate before/after comparison
- [ ] Export to CSV
**Effort:** 3 hours | **Skill:** PowerShell + benchmarking

---

## 🔧 Development Setup

### Prerequisites
- Windows 10/11 + PowerShell 5.1+ (PowerShell 7 preferred)
- Git
- A gaming PC for testing (recommended)
- Administrator privileges

### Clone & Setup
```powershell
git clone https://github.com/Codyte/Ram-Otimizador.git
cd Ram-Otimizador

# Run in development mode (no auto-execute installation)
.\INICIAR.bat
```

### Test Your Changes
1. Edit script files (e.g., `LimparRAM-Inteligente.ps1`)
2. Run menu option 3 (Monitor em tempo real)
3. Watch logs: `Menu > 8`

---

## 📋 Development Workflow

1. **Fork** the repository
2. **Create branch:** `git checkout -b feature/my-feature`
3. **Make changes** and test thoroughly
4. **Commit:** `git commit -m "feat: add valorant detection"`
5. **Push:** `git push origin feature/my-feature`
6. **Create PR** with description

---

## 💡 Code Guidelines

### PowerShell Style
- Use **PascalCase** for functions
- Add comment blocks for complex logic
- Test on both PowerShell 5.1 and 7
- Handle errors gracefully

### Configuration
- Keep `RamCleanerConfig.json` simple
- Document all new settings
- Provide sensible defaults

### Testing
- Test on **Windows 10 and 11**
- Test with **multiple games** (low-RAM, high-RAM)
- Verify **no crashes** during aggressive cleaning
- Check **logs** for errors

---

## 🐛 Bug Reports

Found an issue? Create an issue with:

1. **Title:** Clear, one-liner
2. **Setup:** Your PC specs (RAM, GPU, OS)
3. **Game:** What were you playing?
4. **Steps to reproduce**
5. **Expected vs actual**
6. **Logs:** Paste error lines from logs

Example:
```
Title: Rust detection not working on my PC

Setup: Windows 11, 32GB RAM, RTX 4070
Game: Rust (launched via Steam)

Steps:
1. Launched Rust
2. Opened menu > 3 (Monitor)
3. Game not detected

Expected: "[GAMING] Rust detected"
Actual: "[INFO] Monitoring.." (no game detected)

Logs:
[DEBUG] Checking processes... Rust.exe found at C:\...
[DEBUG] GameDetection returned: false
```

---

## 📝 Commit Message Format

Use conventional commits:
- `feat:` — new feature
- `fix:` — bug fix
- `docs:` — documentation
- `refactor:` — code reorganization
- `test:` — tests
- `perf:` — performance improvement

Examples:
```
feat: add valorant to game detection
fix: crash when RAM at 100%
docs: translate menu to english
perf: reduce cleanup overhead by 20%
```

---

## 🤝 Community & Questions

- **Questions?** Open a GitHub discussion
- **Feature ideas?** Create an issue with `enhancement` label
- **Gaming suggestions?** Tell us what game you want optimized!

---

## 🎯 PR Checklist

Before submitting:
- [ ] Tested on Windows 10 and 11
- [ ] Tested with multiple games
- [ ] No crashes or errors in logs
- [ ] Code follows style guidelines
- [ ] Commit messages are clear
- [ ] No unrelated changes

---

## 📚 Resources

- [Windows Memory Management](https://docs.microsoft.com/en-us/windows/win32/memory/memory-management)
- [PowerShell Docs](https://docs.microsoft.com/powershell/)
- [RAMMap Guide](https://learn.microsoft.com/en-us/sysinternals/downloads/rammap)
- [Game Performance Optimization](https://www.nvidia.com/en-us/geforce/performance-tips/)

---

**Thank you for contributing! Every bit helps gamers run their games smoother. 🚀**