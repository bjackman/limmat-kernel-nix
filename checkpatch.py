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

def git(*args):
    result = subprocess.run(
        ["git"] + list(args),
        capture_output=True, text=True, check=True,
    )
    return result.stdout.strip()

def log_n1(format):
    return git("log", "-n1", "--format=" + format, LIMMAT_COMMIT)

# Workaround for lack of:
# https://github.com/bjackman/limmat/pull/39
# Just use current notes from HEAD. This will require disabling caching, and
# restarting limmat when the notes change. Instead we should take
# LIMMAT_NOTES_OBJECT from the environment once Limmat can provide it.
def get_limmat_notes_object() -> str:
    try:
        return git("notes", "--ref=limmat", "list", "HEAD")
    except subprocess.CalledProcessError as e:
        # Not sure if this is documented but empirically this means no notes
        if e.returncode == 1:
            return None
        raise
LIMMAT_NOTES_OBJECT = get_limmat_notes_object()

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

# This lets you run `git notes --ref limmat edit $COMMIT` and write something
# like checkpatch-ignore=FOO,BAR in there to ignore FOO and BAR for that commit
# without modifying the commit. This is coupled with the by_commit_with_notes
# setting on the Limmat job definition.
def ignores_from_notes() -> list[str]:
    if LIMMAT_NOTES_OBJECT is None:
        return []
    note = git("cat-file", "-p", LIMMAT_NOTES_OBJECT)
    ret = []
    for line in note.splitlines():
        if not line.strip():
            continue
        parts = line.split("=")
        if len(parts) != 2:
            print(f"Ignoring malformed line in limmat commit notes: {line}")
            continue
        k, v = parts
        if k != "checkpatch-ignore":
            print(f"Ignoring unknown setting {k!r} in limmat commit notes.")
            continue

        for item in v.split(","):
            ret.append(item.strip())

    return ret

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
    "NEW_TYPEDEFS",           # yeah yeah yeah
    "EXPORT_SYMBOL",          # noisy
    "EMBEDDED_FUNCTION_NAME", # noisy
    # Will let b4 prep --check identify this for me at the last minute. For now
    # it's useful to have this so I can upload changes to Gerrit for internal
    # review at Google
    "GERRIT_CHANGE_ID"
] + ignores_from_notes()

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
