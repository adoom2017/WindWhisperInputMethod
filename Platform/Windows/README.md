# Windows TSF development

The Windows adapter is intended to build as `fy_tsf.dll` (x64) and exposes
`CLSID_FengYuTextService` through the standard COM entry points. A complete
machine test requires Windows 10/11, Visual Studio 2022, and WiX 4.

```powershell
cmake -S . -B build/windows -A x64
cmake --build build/windows --config Release
ctest --test-dir build/windows -C Release --output-on-failure
```

The current MSI file is a scaffold and must not be treated as installable until
COM registration, TSF profile registration, rollback, and uninstall have passed
the gates in `docs/WINDOWS_HANDOFF.md`.

After those gates pass, install the MSI as administrator, enable WindWhisper
under **Settings > Time & language > Language & region > Chinese > Language
options**, and verify
`nihao`, `haishiyiyang`, `womenkeyiyiqi`, `-`/`=`, `ni~`, and switching the
traditional option in Notepad, WordPad, a WPF textbox, and a Chromium textbox.
After uninstall, the `%LOCALAPPDATA%\\WindWhisper\\InputMethod` directory and
`custom_words.tsv` must remain intact.
