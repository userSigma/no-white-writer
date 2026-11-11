# Inno Setup Windows Distribution Design

## Authorization and scope

The user requested Inno Setup support on 2026-11-06 and explicitly approved the complete integration: a local build command, release-workflow integration, per-user installation without elevation, and upgrades/uninstalls that always retain works and settings. Execute inline without subagents, Git commits, automatic publication, ACL changes, or termination of preexisting processes. Preserve all earlier worktree changes.

## Installer contract

- Product: 不白写作; executable: `no_white_writer.exe`; Windows x64 Release only.
- Keep the existing planned AppId `ce99ca45-fdcf-4d6f-8f1c-74f7dd3b086b`, so subsequent installers update the same installation.
- Install under `%LOCALAPPDATA%\Programs\不白写作` with `PrivilegesRequired=lowest`. Create a per-user Start menu shortcut and an optional, initially unchecked desktop shortcut. Retain the existing application icon.
- Copy the complete validated Release runtime bundle, including Flutter/plugin assets. Exclude build-only debug/linker files. Stage application-local Microsoft VC++ redistributable DLLs from the Visual Studio redistributable directory rather than requiring an elevated runtime installer or copying arbitrary DLLs from System32.
- Read the semantic version and numeric build number from [pubspec](<C:/Users/userSigma/no-white-writer/pubspec.yaml>). Keep the full version for display and the four-component numeric version for Windows metadata; do not bump the project version merely to add packaging. Reject a missing/incomplete Release bundle or a mismatching executable version.
- Use the standard Inno wizard and the project icon. English compiler-default wizard messages are acceptable in this first integration; product identity and project-specific safety messages remain readable. No custom wizard artwork or new online runtime downloads.
- Keep ZIP distribution. Add `no-white-writer-<base-version>-windows-x64-setup.exe` and a matching `.sha256` sidecar to the existing release assets. Output under the ignored build directory, refuse accidental overwriting, and document unsigned/SmartScreen expectations.

## Upgrade, running application, and uninstall safety

- Retain the fixed AppId and previous install location for normal in-place updates.
- Disable automatic application shutdown/restart. Before replacing or uninstalling the installed executable, probe whether it can be opened exclusively for replacement; if it is busy or inaccessible, stop with a message asking the user to save and close the application. Never force-kill a process, delete an instance lock, or bypass the application's save/IME guards.
- The installer only owns installed application files, its own uninstall registration, and its shortcuts. Do not introduce wildcard cleanup of application/data directories, `[UninstallDelete]` rules, user-data deletion code, or a purge-data checkbox.
- `%APPDATA%\不白写作`, exported works, backups, and custom data roots are never installation payload or uninstall targets. This approved policy supersedes the contradictory older purge-checkbox wording in the [root plan](<C:/Users/userSigma/no-white-writer/PLAN.md#L152>).
- Offer launching after an interactive installation, but never launch automatically in silent installation/upgrade tests.

## Implementation boundaries

- `installer/no_white_writer.iss`: installation layout, shortcuts, per-user registration, busy-file guard, and safe uninstall policy.
- `tool/installer_config.dart`: testable version, compiler-path, x64/Release validation and invocation configuration.
- `tool/build_windows_installer.dart`: fresh Release build by default; optional explicit reuse of an already built bundle; compiler/runtime discovery; isolated staging; ISCC invocation; SHA-256 output. Use Dart so local PowerShell script execution policy is not bypassed.
- The existing [CI workflow](<C:/Users/userSigma/no-white-writer/.github/workflows/ci.yml>) verifies installer compilation on Windows. The existing [Release workflow](<C:/Users/userSigma/no-white-writer/.github/workflows/release.yml>) adds installer/hash assets alongside ZIP assets, without changing trigger, permissions, publishing credentials, or actually pushing a tag here.
- [README](<C:/Users/userSigma/no-white-writer/README.md>) and [release documentation](<C:/Users/userSigma/no-white-writer/docs/版本控制与发布规范.md>) document prerequisites, one-command builds, outputs, data retention, and unsigned distribution. Keep unrelated historical feature descriptions out of this change.

## Verification and limits

1. Add failing tests before implementation for semantic/numeric version conversion, compiler discovery, required AOT/assets/x64 inputs, missing runtime files, output refusal, installer retention/running-app contracts, and workflow asset integration. Keep Linux quality tests independent of a Windows compiler.
2. Run the focused tests, fresh analysis/format/diff checks and the serial full test suite.
3. Build a fresh Windows Release and compile a real installer with the available per-user compiler. Verify output metadata and SHA-256.
4. Exercise install/reinstall/uninstall using a separately compiled test AppId, disposable directories and disabled shortcuts/autorun. Preserve untracked canary data and compare existing work hashes; never overwrite a real installation or unregister its AppId. Treat any environment-blocked foreground automation as a documented limitation, not a pass.
5. Deliver a full installer from an ordinary output directory, not a Low-integrity build-tree executable. Do not claim remote Actions execution, code signing, SmartScreen reputation, or a clean-machine/runtime matrix that was not actually tested.

## Completion evidence — 2026-11-06

Implemented the approved installer, Dart packaging command, CI/Release integration and retention documentation. The full serial suite passed **428 tests**, analysis/format/diff gates passed, a fresh Windows Release was built and **Inno Setup 6.7.3** compiled the setup. An isolated test AppId passed install, same-build reinstall, running-app refusal and uninstall: 32 payload files verified, three private canaries retained, 13 existing default-data files (eight work files) unchanged, production registration untouched.

The ordinary Downloads setup and checksum, exact hashes, logs, negative-input/resource-version checks and untested boundaries are recorded in the [implementation plan](<../plans/2026-11-06-inno-setup.md#L79>). No higher-version migration, interactive default-location/shortcut matrix, clean-machine testing, remote Actions, signing or publication is claimed. No subagents, Git commits, ACL changes or preexisting-process termination were used.

## Reference checks

- Inno [CloseApplications documentation](https://jrsoftware.org/ishelp/topic_setup_closeapplications.htm) states that even `yes` closes applications during silent setup; this design therefore uses `no` and a non-destructive busy-file guard.
- Inno [architecture documentation](https://jrsoftware.org/ishelp/topic_setup_architecturesallowed.htm) recommends `x64compatible` for x64 application binaries. Only x64 binaries are built here; ARM64-native packaging is not added.
