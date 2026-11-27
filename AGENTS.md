# Engramma development

- Runtime: Bash 5 and Python standard library on Linux/WSL. Program code and private archives have separate roots.
- Read `README.md`, `CONTRIBUTING.md` and the relevant pages of `docs/` before changing behavior.
- Keep native Claude memory as the first supported memory workflow. Codex configuration exists; broader agent memory support needs its own proposal and tests.
- Use fake archives and isolated HOME, XDG and Claude directories for tests. Never run setup, sync or migration against the maintainer's live archives to verify a change.
- Preserve originals on copy, backup, link and Git failures. Never resolve divergent data by overwriting it.
- Keep runtime code in English and user-facing text in Italian. Do not introduce runtime Node dependencies for developer tools.
- Run focused tests while working and the complete suite once before delivery. Run `make lint` and the relevant tool checks.
- Keep examples generic. Do not import personal notes, archive contents, credentials or private Git history.
- Publishing, tagging releases and migrating real projects require explicit user authorization. Do not change Git identity.
