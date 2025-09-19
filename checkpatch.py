"""
Opinionated wrapper for checkpatch.pl. Expects to run in a Limmat job.
"""

import subprocess
import os

LIMMAT_COMMIT = os.getenv("LIMMAT_COMMIT")
if LIMMAT_COMMIT is None:
    # Probably you are running this script manually, it's designed to be run by
    # Limmat. You can test it by just setting the env var though.
    raise RuntimeError("LIMMAT_COMMIT missing from env")

def log_n1(format):
    result = subprocess.run(
        ["git", "log", "-n1", "--format=" + format, LIMMAT_COMMIT],
        capture_output=True, text=True, check=True,
    )
    return result.stdout.strip()

# Linus doesn't sign off his release commits lol.
author = log_n1("%an")
if author == "Linus Torvalds":
    print("Ignoring patch from Linus")
    exit(0)

# Don't complain about b4 cover-letter commits.
raw_msg = log_n1("%B")
if "\n--- b4-submit-tracking ---\n" in raw_msg:
    print("Ignoring b4-submit-tracking patch")
    exit(0)

ignore = [
    "FILE_PATH_CHANGES",      # Annoying
    "AVOID_BUG",              # yeah yeah yeah
    "VSPRINTF_SPECIFIER_PX",  # Usually I'm doing this deliberately.
    "COMMIT_LOG_LONG_LINE",   # Too noisy
    "MACRO_ARG_UNUSED",       # Bullshit
    "CONFIG_DESCRIPTION",     # Bullshit
    "COMMIT_MESSAGE",         # yeah yeah yeah
    "LOGGING_CONTINUATION",   # yeah yeah yeah
    "COMPLEX_MACRO",          # yeah yeah yeah
    "LONG_LINE",              # yeah yeah yeah
    "EXPORT_SYMBOL",          # noisy
    "EMBEDDED_FUNCTION_NAME"  # noisy
]

# Ignore more stuff on Google prodkernel trees.
if os.path.exists("./gconfigs"):
    ignore += ["GERRIT_CHANGE_ID", "GIT_COMMIT_ID", "MISSING_SIGN_OFF"]

cmd = [
    "scripts/checkpatch.pl", "--git", "--show-types",
    f"--ignore={','.join(ignore)}", "--codespell", LIMMAT_COMMIT
]

try:
    subprocess.run(cmd, check=True)
except subprocess.CalledProcessError:
    exit(1)
