"""
Sets the required Worker environment before any test module imports
`app.main` (pydantic-settings validates `WORKER_INTERNAL_TOKEN` at import
time). Test-only value — never a real secret, never logged.
"""
import os

os.environ.setdefault("WORKER_INTERNAL_TOKEN", "test-only-not-a-real-secret-" + "x" * 16)
