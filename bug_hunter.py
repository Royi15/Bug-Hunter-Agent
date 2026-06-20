#!/usr/bin/env python3
# test hook

import os
import sys
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import google.generativeai as genai
import google.api_core.exceptions as google_errors
from dotenv import load_dotenv

load_dotenv()

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
MODEL_NAME = "gemini-3.1-flash-lite"
OUTPUT_DIR = Path("bug_hunter_output")
USE_DOCKER = False  # set in main() after prompting the user

SUPPORTED_EXTENSIONS = {
    ".py":   ("Python",      "pytest"),
    ".js":   ("JavaScript",  "jest"),
    ".ts":   ("TypeScript",  "jest"),
    ".c":    ("C",           "pytest"),
    ".cpp":  ("C++",         "pytest"),
    ".java": ("Java",        "pytest"),
    ".go":   ("Go",          "pytest"),
    ".rs":   ("Rust",        "pytest"),
    ".rb":   ("Ruby",        "pytest"),
    ".php":  ("PHP",         "pytest"),
    ".cs":   ("C#",          "pytest"),
    ".kt":   ("Kotlin",      "pytest"),
    ".swift":("Swift",       "pytest"),
}

# ─── Module 1: Code Ingestion ─────────────────────────────────────────────────

def ingest_source(file_path: str):
    path = Path(file_path)
    if not path.exists():
        print(f"[ERROR] File not found: {file_path}")
        sys.exit(1)

    ext = path.suffix.lower()
    if ext not in SUPPORTED_EXTENSIONS:
        supported = "  ".join(sorted(SUPPORTED_EXTENSIONS))
        print(f"[ERROR] Unsupported file type '{ext}'. Only code files are accepted.")
        print(f"        Supported extensions: {supported}")
        sys.exit(1)

    source_code = path.read_text(encoding="utf-8")
    language, framework = SUPPORTED_EXTENSIONS[ext]
    module_name = path.stem  # e.g. "sample_code" for "sample_code.py"

    print(f"[1/4] Ingested '{path.name}'  ({language}, {len(source_code)} chars)")
    return source_code, language, framework, module_name


# ─── Module 2: Test Generation Engine ────────────────────────────────────────

TEST_GEN_SYSTEM = """You are an adversarial QA engineer. Your only goal is to FIND BUGS — not to confirm
that the code works. Assume the implementation is broken until proven otherwise.

STEP 1 — VALIDATE THE INPUT
Decide: does the content look like real, intentional source code?
Reject random text, gibberish, prose, CSV/JSON data, or anything clearly not source code
even if the file extension matches.

If INVALID, return ONLY this JSON:
{
    "is_valid_code": false,
    "rejection_reason": "<one sentence>",
    "test_framework": null,
    "test_file_name": null,
    "test_code": null,
    "test_cases": []
}

STEP 2 — DETERMINE INTENDED BEHAVIOUR (read the contract, ignore the implementation)
For each function/class, derive what it is SUPPOSED to do from:
  - Its NAME  (e.g. "add_numbers" must add, never subtract)
  - Its DOCSTRING and inline comments
  - Its PARAMETER NAMES and TYPE HINTS
  - Mathematical or logical first-principles  (factorial(5) is always 120, period)

*** CRITICAL — NEVER derive expected values by tracing through the implementation. ***
Reading the code to decide what to assert is FORBIDDEN. The code may be WRONG.
Your tests must be capable of catching that wrongness.

STEP 3 — RESOLVE AMBIGUOUS INTENT (before writing a single test)
When the code's intended behaviour for an edge case is not obvious, use this
priority order to decide what the correct behaviour SHOULD be:

  1. DOCSTRING / COMMENTS say so explicitly
       → follow them exactly
       → e.g. "raises ValueError if x is negative" → test that it raises ValueError
  2. FUNCTION NAME is a strong signal
       → "safe_divide"  implies zero must be handled gracefully (no crash)
       → "raw_divide"   implies the caller is responsible — but still test it
       → "parse_int"    implies it should handle non-numeric strings, not crash
  3. NO EXPLICIT SIGNAL → default to "the function should handle it safely"
       → Missing error handling in the implementation is NOT intentional design.
          It is a BUG. Write the test that expects safe/correct behaviour and
          let it FAIL on the broken code. That failure is the whole point.

*** NEVER use pytest.raises() (or equivalent) unless the function's name or  ***
*** docstring explicitly promises to raise that exception. If you write       ***
*** pytest.raises(ZeroDivisionError) just because the code crashes on zero,  ***
*** you are testing the bug, not catching it. That is forbidden.              ***

STEP 4 — WRITE ADVERSARIAL TESTS
Write tests that will FAIL when the implementation is incorrect. Cover:
  - Typical inputs with correct outputs YOU computed independently, not from the code
  - Boundary values: 0, 1, -1, empty string/list, None, max/min integers
  - Edge cases: duplicates, already-sorted input, single-element collections
  - Error conditions: invalid types, out-of-range inputs, division by zero
  - Regression traps for common bugs:
      * off-by-one errors (e.g. < vs <=, range(n) vs range(n+1))
      * wrong operator (+ instead of *, and instead of or)
      * mutating the input instead of returning a new value
      * returning the wrong variable or forgetting a return statement
      * incorrect handling of negative numbers or zero

Example rule: if a function is named "is_palindrome", your test MUST assert
is_palindrome("hello") == False. Never write an assertion that merely mirrors
what the implementation happens to return — that defeats the entire purpose.

STEP 5 — POPULATE THE RESPONSE FIELDS
is_valid_code    : true
rejection_reason : null (or a one-sentence explanation if invalid)
test_framework   : "pytest" or "jest"
test_file_name   : e.g. "test_generated_code.py"
test_code        : the complete, runnable test file as a single string
test_cases       : short description of each test case"""


def _call_gemini(model, prompt: str):
    """Call Gemini and surface API errors as clean user-facing messages."""
    try:
        return model.generate_content(prompt)
    except google_errors.ResourceExhausted:
        print("[ERROR] Gemini rate limit exceeded (free tier). Wait a minute and try again.")
        sys.exit(1)
    except google_errors.PermissionDenied:
        print("[ERROR] Invalid API key. Check GEMINI_API_KEY in your .env file.")
        sys.exit(1)
    except google_errors.ServiceUnavailable:
        print("[ERROR] Gemini API is temporarily unavailable. Try again in a few moments.")
        sys.exit(1)
    except google_errors.DeadlineExceeded:
        print("[ERROR] Gemini API request timed out. Try again or reduce the file size.")
        sys.exit(1)
    except google_errors.GoogleAPIError as e:
        print(f"[ERROR] Gemini API error: {e.message if hasattr(e, 'message') else e}")
        sys.exit(1)


TEST_GEN_SCHEMA = {
    "type": "object",
    "properties": {
        "is_valid_code":    {"type": "boolean"},
        "rejection_reason": {"type": "string"},
        "test_framework":   {"type": "string"},
        "test_file_name":   {"type": "string"},
        "test_code":        {"type": "string"},
        "test_cases":       {"type": "array", "items": {"type": "string"}},
    },
    "required": ["is_valid_code", "test_cases", "test_code"],
}


def generate_tests(source_code: str, language: str, framework: str, module_name: str) -> dict:
    if not GEMINI_API_KEY:
        print("[ERROR] GEMINI_API_KEY is not set. Add it to your .env file.")
        sys.exit(1)

    genai.configure(api_key=GEMINI_API_KEY)
    model = genai.GenerativeModel(
        MODEL_NAME,
        system_instruction=TEST_GEN_SYSTEM,
        generation_config=genai.GenerationConfig(
            response_mime_type="application/json",
            response_schema=TEST_GEN_SCHEMA,
        ),
    )

    prompt = (
        f"Language: {language}\n"
        f"Test framework: {framework}\n"
        f"Source module name: {module_name}  <-- use this exact name in all import statements\n\n"
        f"Source code:\n```{language.lower()}\n{source_code}\n```"
    )

    print(f"[2/4] Generating tests with {MODEL_NAME}...")
    response = _call_gemini(model, prompt)
    test_data = json.loads(response.text)

    if not test_data.get("is_valid_code", True):
        reason = test_data.get("rejection_reason", "Content does not look like source code.")
        print(f"[ERROR] Gemini rejected the file: {reason}")
        sys.exit(1)

    n = len(test_data.get("test_cases", []))
    print(f"       {n} test case(s) planned via {test_data.get('test_framework', framework)}")
    return test_data


# ─── Docker Support ───────────────────────────────────────────────────────────

def _check_docker_installed() -> bool:
    try:
        result = subprocess.run(
            ["docker", "--version"], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=10
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def _prompt_run_mode() -> bool:
    """Ask user Docker vs local. Returns True for Docker."""
    print("\n  Docker is available. Where would you like to run the tests?")
    print("  1. Run locally   (uses your system Python / Node)")
    print("  2. Run in Docker (isolated container — make sure Docker is running)")
    while True:
        choice = input("  Your choice (1/2): ").strip()
        if choice == "1":
            return False
        if choice == "2":
            return True
        print("  Please enter 1 or 2.")


def _prompt_proceed_without_docker() -> bool:
    """Warn that Docker is absent; ask whether to proceed locally. Returns True to continue."""
    print("\n[WARNING] Docker is not installed on this machine.")
    print("          Tests will run locally using your system Python / Node.")
    while True:
        ans = input("  Proceed locally? (Y/N): ").strip().upper()
        if ans == "Y":
            return True
        if ans == "N":
            return False
        print("  Please enter Y or N.")


def _resolve_docker_mode() -> bool:
    """
    Check Docker availability, prompt user, and return True if Docker mode is chosen.
    Calls sys.exit if the user declines to proceed or the daemon is not running.
    """
    if _check_docker_installed():
        use_docker = _prompt_run_mode()
        if use_docker:
            info = subprocess.run(
                ["docker", "info"], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=15
            )
            if info.returncode != 0:
                print("\n[ERROR] Docker is installed but the daemon is not running.")
                print("        Please open Docker Desktop and try again.")
                sys.exit(1)
        return use_docker
    if not _prompt_proceed_without_docker():
        print("Exiting. Install Docker at https://www.docker.com/get-started and try again.")
        sys.exit(0)
    return False


def _to_docker_path(path: Path) -> str:
    """Convert an absolute path to a Docker volume-mount path (forward slashes)."""
    return str(path.resolve()).replace("\\", "/")


def _run_tests_docker(test_file: Path, framework: str, source_dir: Path):
    """Run the test file inside a throwaway Docker container."""
    with tempfile.TemporaryDirectory() as _tmpdir:
        tmpdir = Path(_tmpdir)

        # Copy every file from source_dir into the container workspace
        for f in source_dir.iterdir():
            if f.is_file():
                shutil.copy(f, tmpdir / f.name)
        # Copy the test file (may already be there if source_dir == OUTPUT_DIR)
        dest = tmpdir / test_file.name
        if not dest.exists():
            shutil.copy(test_file, dest)

        if framework == "jest":
            image = "node:18-slim"
            pkg = tmpdir / "package.json"
            if not pkg.exists():
                pkg.write_text('{"name":"test","version":"1.0.0"}', encoding="utf-8")
            inner = (
                f"npm install jest --save-dev --quiet 2>&1 && "
                f"npx jest {test_file.name} --no-coverage"
            )
            shell = "sh"
        else:  # pytest (default for all other languages)
            image = "python:3.11-slim"
            req = tmpdir / "requirements.txt"
            pip_extras = " -r requirements.txt" if req.exists() else ""
            inner = (
                f"pip install pytest{pip_extras} -q && "
                f"python -m pytest {test_file.name} -v --tb=short -p no:cacheprovider"
            )
            shell = "bash"

        mount = f"{_to_docker_path(tmpdir)}:/app"
        cmd = ["docker", "run", "--rm", "-v", mount, "-w", "/app", image, shell, "-c", inner]

        print(f"[3/4] Running in Docker ({image}) — first run may pull the image...")
        result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300)
        output = result.stdout
        if result.stderr:
            output += "\n" + result.stderr

        if result.returncode != 0 and (
            "Cannot connect to the Docker daemon" in output
            or "docker daemon is not running" in output.lower()
        ):
            print("[ERROR] Docker daemon is not running. Please start Docker Desktop and retry.")
            sys.exit(1)

        passed = result.returncode == 0
        print(f"       Tests {'PASSED' if passed else 'FAILED'}  (exit {result.returncode})")
        return passed, output


# ─── Module 3: Test Executor ──────────────────────────────────────────────────

def run_tests(test_file: Path, framework: str, source_dir: Path):
    if USE_DOCKER:
        return _run_tests_docker(test_file, framework, source_dir)

    if framework == "pytest":
        cmd = [
            "python", "-m", "pytest", str(test_file),
            "-v", "--tb=short",
            "-p", "no:cacheprovider",
        ]
    elif framework == "jest":
        cmd = ["npx", "jest", str(test_file), "--no-coverage"]
    else:
        cmd = [
            "python", "-m", "pytest", str(test_file),
            "-v", "--tb=short",
            "-p", "no:cacheprovider",
        ]

    env = os.environ.copy()
    existing = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = str(source_dir) + (os.pathsep + existing if existing else "")
    env["PYTHONDONTWRITEBYTECODE"] = "1"

    print(f"[3/4] Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env)
    output = result.stdout
    if result.stderr:
        output += "\n" + result.stderr

    passed = result.returncode == 0
    print(f"       Tests {'PASSED' if passed else 'FAILED'}  (exit {result.returncode})")
    return passed, output


# ─── Module 4: Error Analysis Engine ─────────────────────────────────────────

ERROR_ANALYSIS_SYSTEM = """You are a senior QA engineer and debugging expert.

You will receive:
1. The original source code
2. The generated unit tests
3. The raw test-runner error log

Produce a detailed REPORT.md (valid Markdown) that covers:
- A concise summary of every bug or issue found
- Root-cause analysis for each failing test
- Concrete, actionable fix recommendations with code examples where helpful"""


def analyze_errors(source_code: str, test_code: str, error_log: str) -> str:
    genai.configure(api_key=GEMINI_API_KEY)
    model = genai.GenerativeModel(MODEL_NAME, system_instruction=ERROR_ANALYSIS_SYSTEM)

    prompt = (
        f"## Source Code\n```\n{source_code}\n```\n\n"
        f"## Generated Test Code\n```\n{test_code}\n```\n\n"
        f"## Test Execution Error Log\n```\n{error_log}\n```"
    )

    print("[4/4] Analyzing failures with Gemini 3.1 Flash Lite...")
    response = _call_gemini(model, prompt)
    return response.text


# ─── Module 5: Artifact Writer ────────────────────────────────────────────────

def save_artifacts(test_code: str, terminal_output: str, report=None):
    OUTPUT_DIR.mkdir(exist_ok=True)
    (OUTPUT_DIR / "test_generated_code.py").write_text(test_code, encoding="utf-8")
    (OUTPUT_DIR / "terminal_output.log").write_text(terminal_output, encoding="utf-8")
    if report is not None:
        (OUTPUT_DIR / "REPORT.md").write_text(report, encoding="utf-8")


# ─── Module 6: Code Fixer ────────────────────────────────────────────────────

CODE_FIX_SYSTEM = """You are a senior software engineer and bug fixer.

You will receive:
1. The original source code that contains bugs
2. A bug report describing exactly what is wrong and how to fix it

Your task: return the complete, corrected source code with every reported bug fixed.

Rules:
- Return ONLY the raw source code — no markdown fences, no explanations, no change comments.
- Fix every issue described in the bug report.
- Do not change any logic that is unrelated to the reported bugs.
- Preserve the original code style, structure, and formatting."""


def _strip_code_fences(text: str) -> str:
    """Remove markdown code fences if Gemini wraps the output anyway."""
    match = re.search(r"```(?:\w+)?\n(.*?)```", text, re.DOTALL)
    if match:
        return match.group(1).strip()
    return text.strip()


def fix_code(source_code: str, report: str) -> str:
    genai.configure(api_key=GEMINI_API_KEY)
    model = genai.GenerativeModel(MODEL_NAME, system_instruction=CODE_FIX_SYSTEM)

    prompt = (
        f"## Original Source Code\n```\n{source_code}\n```\n\n"
        f"## Bug Report\n{report}"
    )

    print("\n[FIX] Requesting fix from Gemini...")
    response = _call_gemini(model, prompt)
    return _strip_code_fences(response.text)


def verify_fix(test_file: Path, fixed_code: str, module_name: str,
               source_ext: str, framework: str):
    """Re-run the already-generated tests against the fixed code.

    Writes the fixed code to a temp directory under the original module name so
    existing import statements (e.g. 'from sample_code import ...') still resolve,
    regardless of whether the user chose an in-place fix or a renamed copy.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_source = Path(tmpdir) / f"{module_name}{source_ext}"
        tmp_source.write_text(fixed_code, encoding="utf-8")
        return run_tests(test_file, framework, Path(tmpdir))


def prompt_fix_choice() -> int:
    """Present the 3 fix options and return the user's choice (1/2/3)."""
    print("\n" + "─" * 54)
    print("  Bugs found. What would you like to do?")
    print("─" * 54)
    print("  1. Do nothing    — keep the original file as-is")
    print("  2. Create a copy — save the fixed code to a new file")
    print("  3. Fix in place  — overwrite the original file")
    print("─" * 54)
    while True:
        choice = input("  Your choice (1/2/3): ").strip()
        if choice in ("1", "2", "3"):
            return int(choice)
        print("  Please enter 1, 2, or 3.")


# ─── Entry Point ──────────────────────────────────────────────────────────────

def main():
    global USE_DOCKER

    if len(sys.argv) < 2:
        print("Usage: python bug_hunter.py <source_file>")
        print("Example: python bug_hunter.py mycode.py")
        sys.exit(1)

    source_file = sys.argv[1]

    print("=" * 54)
    print("  Bug Hunter Agent")
    print("=" * 54)

    USE_DOCKER = _resolve_docker_mode()

    # Module 1 — Code Ingestion
    source_code, language, framework, module_name = ingest_source(source_file)

    # Module 2 — Test Generation
    test_data = generate_tests(source_code, language, framework, module_name)
    test_code = test_data["test_code"]

    OUTPUT_DIR.mkdir(exist_ok=True)
    test_file_name = test_data.get("test_file_name", "test_generated_code.py")
    test_file = OUTPUT_DIR / test_file_name
    test_file.write_text(test_code, encoding="utf-8")

    # Module 3 — Test Execution
    source_dir = Path(source_file).resolve().parent
    passed, terminal_output = run_tests(test_file, test_data.get("test_framework", framework), source_dir)

    if passed:
        print("\n[ALL TESTS PASSED] Saving logs & ending.")
        save_artifacts(test_code, terminal_output)
        fixed_path = None
    else:
        # Module 4 — Error Analysis
        report = analyze_errors(source_code, test_code, terminal_output)
        save_artifacts(test_code, terminal_output, report)

        # Module 6 — Code Fixer (with verify-and-retry loop)
        fixed_path = None
        current_source = source_code
        source_path = Path(source_file).resolve()
        source_ext = source_path.suffix

        while True:
            choice = prompt_fix_choice()
            if choice == 1:
                break

            fixed_code = fix_code(current_source, report)

            if choice == 2:
                fixed_path = source_path.parent / f"{source_path.stem}_fixed{source_ext}"
                fixed_path.write_text(fixed_code, encoding="utf-8")
                print(f"[FIX] Fixed copy saved to: {fixed_path}")
            else:
                source_path.write_text(fixed_code, encoding="utf-8")
                print(f"[FIX] Original file updated: {source_path}")

            # Verify using the same generated tests
            print("[VERIFY] Re-running existing tests against the fixed code...")
            fix_passed, fix_output = verify_fix(
                test_file, fixed_code, module_name, source_ext,
                test_data.get("test_framework", framework)
            )
            (OUTPUT_DIR / "terminal_output.log").write_text(fix_output, encoding="utf-8")

            if fix_passed:
                print("[VERIFY] All tests passed — fix confirmed!")
                break

            print("[VERIFY] Tests still failing. Re-analyzing...")
            current_source = fixed_code
            report = analyze_errors(current_source, test_code, fix_output)
            save_artifacts(test_code, fix_output, report)

    print("\n" + "=" * 54)
    print(f"  Artifacts saved to: {OUTPUT_DIR}/")
    print(f"    test_generated_code.py  (unit tests)")
    print(f"    terminal_output.log     (raw console log)")
    if not passed:
        print(f"    REPORT.md               (bug analysis)")
    if fixed_path:
        print(f"\n  Fixed copy: {fixed_path}")
    print("=" * 54)


if __name__ == "__main__":
    main()
