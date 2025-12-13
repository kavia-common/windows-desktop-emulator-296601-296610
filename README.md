# windows-desktop-emulator-296601-296610

Database container notes:
- PostgreSQL defaults to port 5001 for previews (falls back to 5000 if 5001 unavailable).
- Connection: psql postgresql://appuser:dbuser123@localhost:5001/myapp
- Schema includes: users, desktop_sessions, desktop_icons, desktop_windows, taskbar_items, settings.
- Seed: one default desktop session and icons ("My Computer", "Recycle Bin").