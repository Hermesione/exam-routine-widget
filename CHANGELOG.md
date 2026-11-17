# Changelog

All notable changes to Exam Routine Widget are documented here.
Versions follow [Semantic Versioning](https://semver.org/).

## 1.0.0 - 2026-11-17

Initial public release.

### Added

- Desktop exam-routine card: always on the desktop layer, click-through, hidden from
  Alt-Tab and the taskbar, reappears after `Win + D`.
- Live countdown badges, next-exam highlight and automatic removal of finished exams.
- GUI editor with live card preview, card title and footer fields, and accent colour
  controls with WCAG contrast protection.
- Layout system: 9 anchors or free position, 70-150% scale, monitor memory, drag and
  resize directly on the desktop, 3-minute idle auto-lock.
- Tray menu: open editor, edit layout, size and position presets, reset layout,
  start with Windows, hide/show card, open data folder, about, exit.
- PNG and PDF export (print/light and desktop/dark styles; A4 or card-sized PDF).
- Data folder `data/` with one-time migration from the old flat layout, rotating
  backups before every write (last 10 kept), and corrupt-file fallback.
- Per-user startup shortcut, off by default.
- Portable ZIP build script and a per-user Inno Setup installer.
- CI: PowerShell parse + logic checks, headless export rendering on every push;
  tagged releases build the ZIP, Setup.exe and SHA256SUMS.

### Notes

- Windows 10/11 only. PowerShell 5.1 (built into Windows) and WPF.
- Mixed-DPI multi-monitor setups use the system DPI scale; per-monitor DPI v2 is not
  implemented because the PowerShell host cannot easily be made per-monitor aware.
- The license is PolyForm Noncommercial 1.0.0: source-available, not OSI open source.
