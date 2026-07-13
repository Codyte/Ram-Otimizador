# Security Policy

## Supported Versions

Currently supporting the latest version of Ram-Otimizador. Please ensure you're running the latest release for all security updates.

| Version | Status |
|---------|--------|
| v1.0+ | ✅ Actively supported |
| < v1.0 | ❌ Not supported |

---

## Reporting a Vulnerability

If you discover a security vulnerability, **please do NOT open a public GitHub issue**. Instead:

1. **Email:** Contact the maintainer directly (check GitHub profile for contact info)
2. **Include:**
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if available)

3. **Response Time:** We aim to respond within 48 hours

---

## Security Considerations

### ✅ What Ram-Otimizador does safely:

- **No external dependencies** — only uses PowerShell and Windows native APIs
- **No telemetry** — all operations are local; nothing is sent anywhere
- **No installer** — it's pure scripts; you can read and audit everything
- **Minimal permissions** — only requires admin for memory operations (as expected)
- **Local HTTP server** — runs only on localhost with session-based token authentication

### ⚠️ What you should know:

- **Admin/SYSTEM privileges required** for memory cleanup (unavoidable for the functionality)
- **Scheduled task runs as SYSTEM** — normal for background system maintenance
- **Logs contain sensitive data** — CPU/memory state; store securely if sharing
- **Config file readable** — contains your settings; permissions depend on your system

---

## Best Practices

1. **Keep updated** — pull/install the latest version regularly
2. **Review code** — it's all PowerShell; audit `scripts/` if concerned
3. **Check logs** — monitor `logs/cleanup-history.csv` for unexpected behavior
4. **Run as user** — only elevate to admin when needed (the UI prompts for it)
5. **Antivirus compatible** — PowerShell scripts are well-supported by AV software

---

## Compliance

- **No data collection** — fully complies with GDPR, CCPA, etc.
- **MIT License** — see LICENSE for full terms
- **Windows 10/11** — supported versions maintained by Microsoft

---

**Questions?** Open a GitHub Discussion or contact the maintainer.
