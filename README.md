# Bug Hunter Agent

An AI-powered CLI tool that automatically generates unit tests for your source code, executes them, and — when tests fail — produces a detailed bug report, attempts an AI-generated fix, and verifies the fix by re-running the same tests. The cycle repeats until the tests pass or you choose to stop.

Powered by **Gemini 3.1 Flash Lite** via the free Google AI Studio API.

> **Disclaimer — Read Before Use**
> The agent uses an AI model to generate tests, analyse bugs, and suggest fixes.
> AI-generated output can be incomplete, incorrect, or miss edge cases entirely.
> **You are responsible for reviewing every suggested fix before applying it to production code.**
> The agent is a development aid, not a replacement for human code review.
> It does not guarantee that a passing test suite means your code is fully correct.

---

## How It Works

The agent runs your source file through a six-stage pipeline:

```
┌─────────────────────────────────────────────────────┐
│                  Your Source Code                   │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│  1. Code Ingestion                                  │
│     - Validates file extension against supported    │
│       language list                                 │
│     - Reads the source file from disk               │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│  2. Test Generation  (Gemini 3.1 Flash Lite)        │
│     - Verifies the content is real source code      │
│     - Derives expected behaviour from function      │
│       names, docstrings, and type hints — NOT from  │
│       tracing through the implementation            │
│     - Generates adversarial unit tests              │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│  3. Test Executor                                   │
│     - Saves generated tests to bug_hunter_output/   │
│     - Runs pytest / jest locally  OR  in Docker     │
│     - Captures stdout and stderr                    │
└──────────────┬──────────────────────┬───────────────┘
               │                      │
          [PASSED]                [FAILED]
               │                      │
               ▼                      ▼
   Save logs & end     ┌──────────────────────────────┐
                       │  4. Error Analysis Engine    │
                       │     (Gemini 3.1 Flash Lite)  │
                       │     - Source + Tests + Log   │
                       │     - Root-cause analysis    │
                       └──────────────┬───────────────┘
                                      │
                                      ▼
                       ┌──────────────────────────────┐
                       │  5. Artifacts                │
                       │     bug_hunter_output/       │
                       │     ├── test_generated.py   │
                       │     ├── terminal_output.log │
                       │     └── REPORT.md           │
                       └──────────────┬───────────────┘
                                      │
                                      ▼
                       ┌──────────────────────────────┐
                       │  6. Code Fixer               │
                       │     (Gemini 3.1 Flash Lite)  │
                       │                              │
                       │  User picks:                 │
                       │  1. Do nothing               │
                       │  2. Save fix as a new file   │
                       │  3. Overwrite original file  │
                       └──────────────┬───────────────┘
                                      │
                                      ▼
                       ┌──────────────────────────────┐
                       │  Verification                │
                       │  Re-runs the same tests on   │
                       │  the fixed code (no new API  │
                       │  call — zero extra tokens)   │
                       └──────┬───────────────┬───────┘
                              │               │
                         [PASSED]         [FAILED]
                              │               │
                              ▼               ▼
                           Done!       Re-analyse & loop
                                       back to step 6
```

---

## Requirements

- Python 3.9+
- A free **Gemini API key** (see below)
- `pytest` for Python files, `jest` for JS/TS files (only needed for **local** execution)
- **Docker Desktop** *(optional)* — for sandboxed container execution (see [Docker Support](#docker-support))
- **Bash** — required for the hooks (see note below)

### Bash on Windows

The hooks are shell scripts and need a `bash` interpreter. On **macOS and Linux** this is available out of the box. On **Windows** you need one of the following:

- **Git for Windows** *(recommended — you probably already have it)* — installs Git Bash and puts `bash.exe` on your PATH automatically. Download at [git-scm.com](https://git-scm.com/download/win).
- **WSL (Windows Subsystem for Linux)** — a full Linux environment inside Windows. Enable it with `wsl --install` in an admin PowerShell.

To verify bash is available after installing, run in your terminal:

```bash
bash --version
```

If you see a version number, the hooks will work. If the command is not found, install Git for Windows first.

> **Note:** The agent itself (`bug_hunter.py`) is pure Python and runs on all platforms without bash. Bash is only needed for the hooks, which are a developer-experience feature. You can still use the agent fully without them.

---

## Installation

### 1. Get a free Gemini API key

Go to **[Google AI Studio](https://aistudio.google.com/app/apikey)**, sign in with your Google account, and click **Create API Key**. It is completely free — no credit card required.

### 2. Clone and install dependencies

```bash
git clone <repo-url>
cd Bug-Hunter-Agent
pip install -r requirements.txt
```

### 3. Add your API key

Open `.env` and replace the placeholder:

```env
GEMINI_API_KEY=your_actual_key_here
```

> The `.env` file is gitignored and will never be committed.

### 4. (Optional) Install pytest

If you don't already have it:

```bash
pip install pytest
```

---

## Usage

```bash
python bug_hunter.py <path/to/your/source_file>
```

**Examples:**

```bash
python bug_hunter.py mycode.py
python bug_hunter.py src/utils.js
python bug_hunter.py lib/parser.ts
```

**Sample output — tests failed, fix applied and verified:**

```
══════════════════════════════════════════════════════
  Bug Hunter Agent
══════════════════════════════════════════════════════

  Docker is available. Where would you like to run the tests?
  1. Run locally   (uses your system Python / Node)
  2. Run in Docker (isolated container — make sure Docker is running)
  Your choice (1/2): 1

[1/4] Ingested 'mycode.py'  (Python, 842 chars)
[2/4] Generating tests with gemini-3.1-flash-lite...
       7 test case(s) planned via pytest
[3/4] Running: python -m pytest bug_hunter_output/test_generated_code.py -v --tb=short
       Tests FAILED  (exit 1)
[4/4] Analyzing failures with Gemini 3.1 Flash Lite...

──────────────────────────────────────────────────────
  Bugs found. What would you like to do?
──────────────────────────────────────────────────────
  1. Do nothing    — keep the original file as-is
  2. Create a copy — save the fixed code to a new file
  3. Fix in place  — overwrite the original file
──────────────────────────────────────────────────────
  Your choice (1/2/3): 2

[FIX] Requesting fix from Gemini...
[FIX] Fixed copy saved to: mycode_fixed.py
[VERIFY] Re-running existing tests against the fixed code...
       Tests PASSED  (exit 0)
[VERIFY] All tests passed — fix confirmed!

══════════════════════════════════════════════════════
  Artifacts saved to: bug_hunter_output/
    test_generated_code.py  (unit tests)
    terminal_output.log     (raw console log)
    REPORT.md               (bug analysis)

  Fixed copy: mycode_fixed.py
══════════════════════════════════════════════════════
```

---

## Docker Support

Every time you run the agent you are asked whether to execute the generated tests locally or inside an isolated Docker container. The decision is made automatically based on what is installed on your machine.

### How the prompt works

**If Docker Desktop is installed:**
```
  Docker is available. Where would you like to run the tests?
  1. Run locally   (uses your system Python / Node)
  2. Run in Docker (isolated container — make sure Docker is running)
  Your choice (1/2):
```
Choosing **2** immediately checks that the Docker daemon is actually running. If Docker Desktop is installed but not open, the agent stops with a clear message instead of silently failing:
```
[ERROR] Docker is installed but the daemon is not running.
        Please open Docker Desktop and try again.
```

**If Docker is not installed:**
```
[WARNING] Docker is not installed on this machine.
          Tests will run locally using your system Python / Node.
  Proceed locally? (Y/N):
```
Answering **N** exits cleanly. Answering **Y** continues with local execution as normal.

### What runs inside the container

| Framework | Docker image | How tests are installed |
|-----------|-------------|------------------------|
| pytest | `python:3.11-slim` | `pip install pytest` (+ `-r requirements.txt` if present) |
| jest | `node:18-slim` | `npm install jest --save-dev` |

The agent copies the source file(s) and the generated test file into a temporary directory, mounts it as `/app` inside the container, runs the tests, and captures the output. The container is discarded after each run (`--rm`).

> **First run:** Docker will pull the image if it is not cached locally. This can take 30–60 seconds. Subsequent runs use the cached image and are much faster.

### Installing Docker

Download **Docker Desktop** for free at [docker.com/get-started](https://www.docker.com/get-started). It is available for Windows, macOS, and Linux.

---

## Output Files

All output is written to `bug_hunter_output/` (gitignored).

| File | Description |
|------|-------------|
| `test_generated_code.py` | The adversarial unit test suite Gemini generated |
| `terminal_output.log` | Raw stdout + stderr from the most recent test run |
| `REPORT.md` | Bug report — only created when tests fail |

`REPORT.md` contains a per-bug breakdown: what failed, the root cause, and a concrete fix recommendation with code examples.

---

## Code Fixer & Verification Loop

When tests fail the agent offers three choices:

| Option | What happens |
|--------|-------------|
| **1 — Do nothing** | Exit. The original file is untouched. |
| **2 — Create a copy** | Gemini's fix is saved as `<name>_fixed.<ext>` next to your original file. Original is never modified. |
| **3 — Fix in place** | Gemini's fix overwrites the original file directly. |

After any fix is saved the agent automatically re-runs the **same tests** against the fixed code — no new API call, no extra tokens spent. If the tests still fail, the error is re-analysed and the menu appears again. You can keep iterating or choose option 1 at any point to stop.

> **Important:** "All tests passed" after a fix means the generated test suite no longer detects the previously found bugs. It does **not** mean the code is production-ready or free of all possible issues. Always review the diff yourself before merging or deploying the fixed code.

---

## Supported Languages

| Extension | Language | Test Runner |
|-----------|----------|-------------|
| `.py` | Python | pytest |
| `.js` | JavaScript | jest |
| `.ts` | TypeScript | jest |
| `.c` | C | pytest |
| `.cpp` | C++ | pytest |
| `.java` | Java | pytest |
| `.go` | Go | pytest |
| `.rs` | Rust | pytest |
| `.rb` | Ruby | pytest |
| `.php` | PHP | pytest |
| `.cs` | C# | pytest |
| `.kt` | Kotlin | pytest |
| `.swift` | Swift | pytest |

Files with unsupported extensions are rejected immediately before any API call is made. Files with a supported extension but non-code content (random text, prose, data files) are rejected by Gemini's content validation step.

---

## Developer Hooks

This project ships with a complete hooks system that runs automatically during every development session. Hooks enforce safety rules, track activity, and clean up after every edit — without you having to think about it.

All hooks live in `.gemini/hooks/`. They are registered in `.gemini/settings.json` and fire automatically.

### Hook Overview

| Hook | Event | Trigger | What It Does |
|------|-------|---------|--------------|
| `pre_command_firewall.sh` | PreToolUse | Bash | Blocks commands matching dangerous regex patterns |
| `pre_rate_limiter.sh` | PreToolUse | Bash | Counts commands per session; warns then blocks when limit is reached |
| `pre_commit_validator.sh` | PreToolUse | Bash | Enforces conventional commit message format |
| `pre_secrets_guard.sh` | PreToolUse | Read | Blocks the AI assistant from reading files listed in `secret_files.txt` |
| `post_auto_backup.sh` | PostToolUse | Edit / Write | Creates a timestamped backup of every edited file |
| `post_syntax_checker.sh` | PostToolUse | Edit / Write | Runs a syntax checker (bash/python/gcc) on the saved file |
| `post_session_summary.sh` | Stop | — | Prints a formatted activity report when the session ends |

### Hook Details

#### `pre_command_firewall.sh`

Reads regex patterns from `config/dangerous_patterns.txt` and blocks any Bash command that matches. If a command is blocked, the AI assistant receives an error message explaining which pattern matched and is asked to use a safer alternative.

**To add a blocked pattern**, open `config/dangerous_patterns.txt` and add a line:
```
# Block shutting down the machine
shutdown\s+
```

#### `pre_rate_limiter.sh`

Tracks the total number of Bash commands run in the current session using `data/.command_count`. Emits a warning when the count exceeds `WARNING_THRESHOLD` and blocks entirely at `MAX_COMMANDS`.

**To reset the counter mid-session**, create the file `data/.reset_commands` (the hook deletes it automatically on next run):
```bash
touch .gemini/hooks/data/.reset_commands
```

#### `pre_commit_validator.sh`

Intercepts `git commit -m "..."` calls and enforces three rules:

1. Message must start with a valid prefix from `config/commit_prefixes.txt`
2. Message length must be between 10 and 72 characters
3. Message must not end with a period

If no prefix is found, the hook analyses the staged diff and suggests one:
- New files → `feat:`
- Test/spec files → `test:`
- Markdown files → `docs:`
- More deletions than insertions → `refactor:`

**To add a new valid prefix**, add it to `config/commit_prefixes.txt` (one per line).

#### `pre_secrets_guard.sh`

Blocks the AI assistant from reading any file listed in `config/secret_files.txt`. Matching is suffix-based and case-insensitive, so `.env` blocks `project/.env`, `C:\Users\..\.env`, etc.

**To protect additional files**, add entries to `config/secret_files.txt`:
```
.env
my_credentials.json
private_key.pem
```

#### `post_auto_backup.sh`

After every Edit or Write, copies the modified file to `data/.backups/<filename>.<timestamp>`. Keeps only the most recent `MAX_BACKUPS` copies per file; older ones are deleted automatically.

All backup activity is logged to `data/session_<id>.log`.

#### `post_syntax_checker.sh`

After every Edit or Write, runs the appropriate syntax checker for the file type:

| Extension | Checker |
|-----------|---------|
| `.sh`, `.bash` | `bash -n` |
| `.py` | `python3 -m py_compile` |
| `.c`, `.h` | `gcc -fsyntax-only` |
| Everything else | Skipped silently |

Syntax errors are reported as warnings (exit 1) — they do not block the session.

#### `post_session_summary.sh`

When the development session ends, reads `data/session_<id>.log` and prints a formatted summary:

```
════════════════════════════════════════
        SESSION SUMMARY REPORT
════════════════════════════════════════
Session: abc123
Period:  2025-05-27 14:00:00 -> 2025-05-27 14:42:17

── Activity ─────────────────────────
  Total actions: 18
  Backups made:  9
  Syntax checks: 9
  Syntax errors: 0

── Most Edited Files ────────────────
  1. bug_hunter.py (6 edits)
  2. hooks.conf (2 edits)
  3. requirements.txt (1 edit)

── File Types ───────────────────────
  .py      files: 7
  .sh      files: 2
```

---

## Hook Configuration Reference

All configuration files are in `.gemini/hooks/config/`.

### `hooks.conf`

Controls the rate limiter and backup rotation:

```ini
# Maximum Bash commands allowed per session before blocking
MAX_COMMANDS=50

# Warn when this threshold is reached (must be < MAX_COMMANDS)
WARNING_THRESHOLD=40

# Max timestamped backups to keep per file
MAX_BACKUPS=5
```

### `dangerous_patterns.txt`

One POSIX extended regex per line. A command matching any pattern is blocked. Lines starting with `#` are comments.

```
# Examples of what is blocked by default:
rm\s+-rf\s+/         # recursive delete of root
dd\s+if=             # raw disk writes
curl.*\|\s*(ba)?sh   # piping remote scripts to shell
```

### `commit_prefixes.txt`

One conventional-commit prefix per line. Any `git commit -m` message that does not start with `<prefix>: ` is blocked.

```
feat
fix
docs
refactor
test
chore
```

### `secret_files.txt`

One filename suffix per line (case-insensitive). The AI assistant cannot read any file whose path ends with a listed entry.

```
.env
.env.local
.env.production
.env.staging
```

---

## Testing the Hooks Locally

Use `hook_runner.sh` to simulate any hook chain without needing a live session:

```bash
# Test the command firewall — should block
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"},"session_id":"test"}' \
  | bash .gemini/hooks/hook_runner.sh PreToolUse Bash

# Test a safe command — should pass
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"session_id":"test"}' \
  | bash .gemini/hooks/hook_runner.sh PreToolUse Bash

# Test the backup + syntax check chain after an edit
echo '{"tool_name":"Edit","tool_input":{"file_path":"bug_hunter.py"},"session_id":"test"}' \
  | bash .gemini/hooks/hook_runner.sh PostToolUse Edit
```

---

## Project Structure

```
Bug-Hunter-Agent/
├── bug_hunter.py              Main agent
├── requirements.txt
├── .env                       Your API key (never committed)
├── .gitignore
└── .gemini/
    ├── settings.json          Registers hooks with the AI assistant
    └── hooks/
        ├── pre_command_firewall.sh
        ├── pre_rate_limiter.sh
        ├── pre_commit_validator.sh
        ├── pre_secrets_guard.sh
        ├── post_auto_backup.sh
        ├── post_syntax_checker.sh
        ├── post_session_summary.sh
        ├── hook_runner.sh         Local hook simulator
        ├── hooks_config.txt       hook_runner.sh routing table
        ├── config/
        │   ├── hooks.conf
        │   ├── dangerous_patterns.txt
        │   ├── commit_prefixes.txt
        │   └── secret_files.txt
        └── data/                  Runtime only — gitignored
            ├── .backups/
            ├── .command_count
            └── session_<id>.log
```

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `GEMINI_API_KEY is not set` | Missing `.env` or empty key | Add your key to `.env` |
| `Rate limit exceeded` | Free tier limit hit | Wait ~1 minute and retry |
| `Invalid API key` | Wrong key in `.env` | Re-copy from Google AI Studio |
| `Unsupported file type` | Extension not in the supported list | Use a supported language file |
| `Gemini rejected the file` | File has the right extension but isn't real code | Pass an actual source code file |
| `ModuleNotFoundError` in tests | Source file not on Python path | The agent sets `PYTHONPATH` automatically — ensure you run from the project root |
| `Docker is installed but the daemon is not running` | Docker Desktop is closed | Open Docker Desktop and wait for it to finish starting, then retry |
| `UnicodeDecodeError` in Docker output | System locale mismatch | Already handled internally — output is read as UTF-8 with replacement characters |
| Docker run hangs for a long time | Image is being pulled on first use | Wait ~60 seconds; subsequent runs are fast once the image is cached |
