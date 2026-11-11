# Inno Setup Support Implementation Plan

> Execute inline with the executing-plans skill. No subagents, Git commits, worktree reset, system permission changes, automatic tag push or termination of preexisting processes. The user already approved complete integration and data retention.

**Goal:** Build a safe per-user Windows x64 installer locally and in CI, publish its hash alongside the existing ZIP, and keep works/settings through upgrades and uninstall.

**Architecture:** A focused Inno script owns installation behavior. A small testable Dart configuration module validates versions/inputs; a separate Dart command builds Release, stages its complete runtime plus application-local VC++ DLLs, invokes ISCC and hashes the output. Workflows call this same command rather than duplicating packaging rules.

**Tech Stack:** Flutter/Dart already pinned by the project, Inno Setup 6 with x64compatible support, Windows Visual Studio redistributable runtime, existing GitHub Actions workflows. No new Flutter runtime dependencies.

---

## Task 1 — Version and build-input contract, test first

Create `test/installer_config_test.dart`, `tool/installer_config.dart`.

- [x] Write actual tests for `parseInstallerVersion(String source)` returning full `0.4.1+5`, base `0.4.1`, and Windows `0.4.1.5`; reject malformed versions, nonnumeric Windows build numbers and components above 65535. Handle a valid prerelease without losing the numeric resource version.
- [x] Test `compilerCandidates(Map<String, String> environment)` with explicit environment override, per-user and Program Files locations. Tests use temporary directories, not installed machine state.
- [x] Test `validateReleaseBundle(Directory source)` for the executable, Flutter engine, AOT file, ICU and asset manifest, validating x64 PE binaries and the x64 ELF AOT snapshot separately. Reject missing/AOT-less/ARM inputs. Test runtime-directory validation for the required VC++ DLLs and safe version-derived output filenames.
- [x] Observe meaningful RED, then implement only the configuration types/functions needed. Run `flutter test --no-pub test/installer_config_test.dart --reporter expanded` to GREEN.

Version test core:

```dart
final version = parseInstallerVersion('name: no_white_writer\nversion: 0.4.1+5\n');
expect(version.full, '0.4.1+5');
expect(version.base, '0.4.1');
expect(version.windows, '0.4.1.5');
```

## Task 2 — Installer behavior and retention contract, test first

Create `test/installer_contract_test.dart`, `installer/no_white_writer.iss`.

- [x] Add failing contract tests for fixed default AppId, `PrivilegesRequired=lowest`, per-user destination, default-unchecked desktop shortcut, complete staged payload, and silent-install autorun disabled.
- [x] Assert `CloseApplications=no`, `RestartApplications=no`, no force-close/process termination API, no AppData deletion, and no `[UninstallDelete]` or wildcard cleanup section. Require a busy-file guard before install and uninstall.
- [x] Implement these exact safety directives:

```ini
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\不白写作
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=no
RestartApplications=no
```

The guard opens an existing `{app}\no_white_writer.exe` with `fmOpenReadWrite or fmShareExclusive`, immediately closes a successful handle, and otherwise returns a save-and-close message from `PrepareToInstall` or rejects `InitializeUninstall`. Do not inspect stale PIDs, kill processes or create/delete the application's instance lock.

- [x] Set display version from validated full version and resource metadata from its four-component version. Use `GetVersionNumbersString` to reject an executable/version mismatch. Keep a preprocessor AppId override solely for isolated smoke-test compilation; the normal Dart command always passes the fixed production AppId.
- [x] Run both new test files and compile with actual ISCC once a fresh Release is available. Compiler errors are not treated as completed checks.

## Task 3 — Single local packaging entry point

Create `tool/build_windows_installer.dart`; extend configuration tests for the exposed deterministic rules.

- [x] Support `dart run tool/build_windows_installer.dart` for fresh Release; explicit `--skip-build`, `--iscc`, `--runtime-dir`, `--source-dir`, `--output-dir` and `--help` for controlled reuse/CI. Fail clearly on unknown arguments, missing compiler/runtime/source and existing output. Do not modify PowerShell execution policy.
- [x] Resolve repo-relative paths from the script, discover the compiler from override/PATH/per-user/Program Files, and discover x64 runtime files only from Visual Studio redistributable directories (vswhere or explicit override), never System32.
- [x] Stage in a new ignored build directory, copy complete runtime/assets while omitting only `.pdb`, `.lib`, `.exp`, then add the redistributable CRT DLLs. Preserve executable version and validate x64/AOT inputs before ISCC.
- [x] Pass version/source/output definitions as argument-list elements to ISCC, propagate a nonzero exit, and verify the installer exists before writing a matching `.sha256` sidecar. Refuse overwriting an existing package/hash instead of deleting previous deliverables.
- [x] Keep compiler and process interaction in this entry point; keep pure configuration tests cross-platform and free of Windows installation side effects.

## Task 4 — CI/CD and documentation

Modify [CI](<C:/Users/userSigma/no-white-writer/.github/workflows/ci.yml>), [Release](<C:/Users/userSigma/no-white-writer/.github/workflows/release.yml>), [README](<C:/Users/userSigma/no-white-writer/README.md>), [release guide](<C:/Users/userSigma/no-white-writer/docs/版本控制与发布规范.md>) and only the affected installer-policy lines in [PLAN](<C:/Users/userSigma/no-white-writer/PLAN.md>).

- [x] Add tests that the Windows job compiles the installer and the Release job includes `*.exe` and `*.sha256` without removing ZIP assets or changing release triggers/permissions.
- [x] Ensure ISCC is available in the hosted Windows job, then call `dart run tool/build_windows_installer.dart --skip-build` after its existing fresh Release build. Include setup/hash in CI diagnostic artifacts and in actual tag-triggered release assets. Do not run or publish remote workflows here.
- [x] Document compiler/runtime prerequisites, default/full and skip-build commands, output names, same-AppId upgrades, data retention, unsigned SmartScreen warnings and standard wizard language. Replace the old contradictory purge-data checkbox wording, but do not revise unrelated historical features.

## Task 5 — Fresh verification and isolated installer smoke test

- [x] Run focused tests, `dart analyze`, format/diff checks, and the entire serial Flutter suite. Record actual counts and failures, not stale logs.
- [x] Build fresh Windows Release and compile a real setup through the new Dart entry point. Record compiler/build output, EXE metadata, size and SHA-256.
- [x] Compile the same installer script with a separate test AppId and disposable output/install directories. Use silent setup with shortcuts/autorun disabled, reinstall the same build, verify installed payload and a non-payload canary, then uninstall and verify canary retention. Inspect only the test registration and uninstall only the test AppId; refuse to touch any preexisting production installation. Compare default work hashes before/after without launching against author works.
- [x] Copy the finished installer into a new ordinary Downloads directory without ACL modification; compare its hash. Do not deliver a Low-integrity build-tree executable as the user-facing entry point.
- [x] Update this plan/spec with fresh results and any limitations (including no remote Actions run, signing/reputation or clean-machine matrix). Deliver the installer and checksum, without committing or discarding any earlier modifications.

## Verification record — 2026-11-06

- TDD: observed failing configuration/installer/workflow contracts before implementation; **37 configuration + 5 contract tests passed**. Corrected an initial test-fixture assumption after inspecting the real Windows Flutter AOT file: it is x64 ELF, not PE; validation now checks each actual format rather than weakening architecture checks.
- Full regression: `flutter test --no-pub --concurrency=1 --reporter expanded` completed with **428 passed, zero failed**, in 5:48. Analysis reported no issues; final formatting checked 108 Dart files with zero changes; `git diff --check` passed.
- Fresh `flutter build windows --release` succeeded in **137.5 seconds** through the new entry point. Actual ISCC is **6.7.3**. Its initial rejection of unsupported `FileOpen` was corrected to the documented `TFileStream.Create` API; final installer compilation succeeded in **19.625 seconds**.
- Both workflows parsed as YAML with triggers/permissions and Release-before-installer/asset contracts intact. All four extracted PowerShell snippets passed UTF-8-aware native AST syntax parsing; they were not executed and no execution policy was bypassed. GitHub Actions itself was not run.
- Isolated native lifecycle: separately compiled test AppId `976b5e20-422a-403d-984e-414c0df7344b`, disposable install directory, shortcuts and automatic launch disabled. Install, same-build reinstall and uninstall returned 0. All **32 payload files** matched staging hashes and were removed on uninstall; **three non-payload canaries** remained. The test uninstall registration was removed; the production registration was unchanged.
- The installed application showed its normal window at **Medium integrity (RID 8192)** and exited normally through its own close handler. While this owned process was running, reinstall returned **7** and uninstall returned **1**, without killing it. After normal close, uninstall succeeded.
- All **13 existing default-data files**, including **eight work files**, retained their hashes. No author works were opened for the smoke test; no preexisting process, instance lock, ACL or production installation was changed.
- Negative native checks also passed: existing output is rejected (exit 1), executable/version mismatch is rejected by ISCC (exit 2), and no mismatched setup is produced. Windows resource version is **0.4.1.5**, display/product version **0.4.1+5**. The binary is **NotSigned**, as expected; padded Windows version strings were normalized only in the diagnostic reader.
- Evidence: [lifecycle result](<../../../build/installer-smoke-20261106-234113/result.json>), [additional metadata/refusal checks](<../../../build/installer-smoke-20261106-234113/additional-checks.json>), [full test log](<../../../build/installer-full-tests.log>) and [latest delivery pointer](<../../../build/installer-verification-latest.json>).

### Final deliverables

- [Windows x64 setup](<C:/Users/userSigma/Downloads/no-white-writer-0.4.1-installer-20261106-234113/no-white-writer-0.4.1-windows-x64-setup.exe>) — **20,825,648 bytes**, written into a new ordinary Downloads directory without changing ACLs.
- [SHA-256 sidecar](<C:/Users/userSigma/Downloads/no-white-writer-0.4.1-installer-20261106-234113/no-white-writer-0.4.1-windows-x64-setup.exe.sha256>).
- SHA-256: `d5d59b0afdcec27a596fec9f62cc9d3bc3e74dece9f19edbf5fba5daf2c5b2ba`; source and delivered setup/sidecar remained byte-identical after verification.

### Remaining verification boundaries

The tested reinstall uses the **same build**, not a fabricated higher-version binary. Higher-version/legacy installation migration, default-location interactive wizard/shortcut behavior, clean-machine and Windows-version matrices, SmartScreen reputation and remote Actions execution remain untested. The installed test used an explicit disposable location so the user's real installation was never replaced. No signing, Git commit, tag push or publication was performed.
