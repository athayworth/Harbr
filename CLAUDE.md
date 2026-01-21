# Claude Code Instructions for Harbr

## Pre-Push Security Checklist

Before committing or pushing code to GitHub, always verify:

### 1. No Secrets in Code
Check for and reject any:
- API keys or tokens
- Passwords or credentials
- Private keys (SSH, SSL, etc.)
- Database connection strings with passwords
- `.env` files with real values
- OAuth client secrets

### 2. No Hardcoded Personal Paths
Check for and replace any absolute paths containing:
- `/Users/username/...` - use `~` or relative paths instead
- Specific machine names or IPs
- Personal directory structures

### 3. No Sensitive Data
- No real email addresses (except in LICENSE/attribution)
- No phone numbers
- No private URLs or internal endpoints

## How to Check

When asked to commit or push, run these checks:

```bash
# Search for potential secrets
grep -r "api_key\|apikey\|secret\|password\|token\|credential" --include="*.swift" --include="*.json" .

# Search for hardcoded user paths (replace 'username' with actual username)
grep -r "/Users/" --include="*.swift" --include="*.json" .
```

If any issues are found, alert the user before proceeding.

## Project-Specific Notes

- Config files are stored in `~/.harbr/` (uses tilde, not absolute path - this is correct)
- The app uses system binaries at standard paths (`/usr/sbin/lsof`, `/bin/kill`) - these are fine
