# LOSP device setup color and roomservice fix

## Changes

Only `build/device_setup.sh` was changed in the repository. The report is stored at `.codex-reference/device-setup-color-roomservice-fix.md`.

### Color output root cause and fix

The old color variables contained the literal characters `\033` and were passed through `printf '%s'`, so terminals printed backslash text instead of an escape byte. `init_colors` now creates actual escape bytes with `printf '\033…'` and helpers emit them with `printf`. The audited helpers (`die`, `section_header`, `prompt_user`, `show_warning`, `show_success`, `show_error`, `add_separator`, and `show_progress`) use `printf` consistently. Progress bar width and text layout remain the same.

Color is enabled only when stdout is a TTY, `NO_COLOR` is unset, and `TERM` is not `dumb`. Redirected output, `NO_COLOR`, and `TERM=dumb` therefore receive empty color variables and plain text. Color variables are initialized at source time and refreshed when the helpers run, so sourcing before an interactive prompt still works. Warning remains yellow, error red, and success green.

The former generic cyan accent is now `LOSP_TEAL`. When `COLORTERM` explicitly advertises `truecolor` or `24bit`, the script emits the exact RGB `#10C8C8` (`16,200,200`) using a generated 24-bit escape sequence. Otherwise it uses standard terminal cyan (`SGR 36`) as the closest widely supported fallback. `TERM` alone is not used to infer true-colour support. The teal accent is limited to headings, prompt text, progress percentage, and the ROM/device/config values previously shown in cyan.

### Stale roomservice root cause and managed block

`rewrite_roomservice_clean` previously removed only the selected device's vendor project and its currently detected common vendor project. Entries from earlier setup runs remained, including old Google device/vendor projects. Those stale declarations could make `repo manifest -r` fail when a declared checkout directory was absent.

The script now replaces the content between `<!-- LOSP managed begin -->` and `<!-- LOSP managed end -->`, preserving content outside the block. It writes the exact current LOSP-owned vendor set: the selected primary vendor project and, for non-Google devices when detected, its common vendor project. A repeated setup replaces the same block with the same entries, with no timestamp and no duplicate project.

For legacy files without markers, migration removes only entries matching the distinctive project format this script itself emitted: `TheMuppets/proprietary_vendor_*` mapped to `vendor/*`. Other XML project entries are preserved. A malformed or multiply repeated marker pair causes a clear failure before rewrite rather than risking removal of unrelated content.

For a husky-to-blazer switch, legacy script-generated husky, shusky, zuma, and shusky-kernels vendor declarations are removed, and the block receives the single blazer project. Unrelated entries remain outside the new block. Repeating blazer setup leaves the managed project list unchanged.

### Sync and validation behavior

After rewrite, `refresh_repo_manifest_view` runs `repo sync -n` only for the current LOSP-managed vendor path(s), allowing repo to refresh its local manifest view without syncing unrelated projects. A refresh failure stops setup with an error. `sync_vendor_repo` then syncs each required managed vendor project and rejects any path not recognized by `repo_project_known`. Existing `verify_vendor_repo` checks the checkout and expected vendor makefile. Finally, `validate_losp_manifest_projects` checks every path inside the managed block is a known repo project with a valid Git checkout. Failures are reported and setup stops before the later ROM build.

No full repo sync or Android build was run. No `vendor/google`, device tree, build/soong, build/make, or repo-tool files were changed.

## Validation performed

- `bash -n build/device_setup.sh` — passed.
- `git diff --check` — passed.
- Focused temporary shell validation — passed for exact RGB output on a true-colour PTY; plain output with inherited `NO_COLOR`, `TERM=dumb`, and redirected stdout; legacy stale Google vendor removal while preserving unrelated projects; blazer appearing once; repeated blazer rewrite being byte-for-byte idempotent; and missing managed checkout being rejected with a clear error.
- The missing-checkout test intentionally emits `LOSP-managed project vendor/google/blazer has no valid checkout after sync` and verifies validation returns failure.
- Validation ran in temporary directories; no live `.repo/local_manifests/roomservice.xml` was present or modified in this workspace.

## Git and history audit

- Working branch: `17.0`.
- Tracking branch: `origin/17.0`; configured remote URL is `https://github.com/Lineage-OS-Special-Project/android_vendor_crdroid.git` for fetch and push.
- At audit time, local `17.0` was 12 commits behind `origin/17.0` and had no local commits after `d1f15b79`.
- Candidate historical commit to amend later: `d1f15b79 envsetup: add LOSP device setup and GMS integration`. `git log --follow -- build/device_setup.sh` shows this is the sole commit that introduced the file.
- If that commit is amended after bringing in the current remote history, the 12 commits currently on `origin/17.0` after it need replaying in order: `2e7e5544`, `a7d609a1`, `97d510eb`, `34bcfe21`, `14a81e84`, `dc0fb9b9`, `31d822d8`, `a317f770`, `fda7d64e`, `30cb677c`, `40a51a08`, `d31f8077` (oldest to newest).
- No Git history or index commands that modify state were run; no commit was made.

## Risks and edge cases

- The exact RGB path trusts the explicit `COLORTERM=truecolor` or `COLORTERM=24bit` signal. Terminals that support true colour but do not advertise it use standard cyan; terminals that advertise it incorrectly may not render the intended teal.
- Legacy migration intentionally treats every project matching the old script's Muppets vendor naming/path format as script-owned. A user-created project with that exact format is indistinguishable from an old LOSP-generated entry and would also be removed.
- A legacy device/common project entry that was manually edited so it no longer matches the emitted project format is preserved as unrelated content. The managed block itself is exact and idempotent going forward.
- Repo manifest refresh and vendor sync behavior was validated through focused shell-level checks and code inspection, not against a live Android checkout.
