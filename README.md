# BlackbeardBot

Discord bot for UBC Sailing Club. Handles member verification via Wild Apricot, opt-in role panels, help-desk ticketing (oops-something-broke), and workhour tracking. Backs up verified member data to Google Drive daily.

---

## Quick Deploy (New Installation)

```bash
git clone https://github.com/ubcsailingclub/BlackbeardBot.git /opt/blackbeard-bot
cd /opt/blackbeard-bot
sudo useradd -r -s /usr/sbin/nologin blackbeard
sudo chown -R blackbeard:blackbeard /opt/blackbeard-bot
sudo make install

# Set up tokens
sudo editor /etc/default/blackbeard-bot
# Set DISCORD_TOKEN, WA_API_KEY, WA_ACCOUNT_ID
# Set GOOGLE_SPREADSHEET_ID, GOOGLE_SERVICE_ACCOUNT_JSON

sudo systemctl enable --now blackbeard-bot
sudo systemctl enable --now blackbeard-backup.timer
```

## Quick Update (After git pull)

```bash
cd /opt/blackbeard-bot
sudo git pull
sudo make build-install
```

`make build-install` does everything:
1. Updates the Python venv and re-installs dependencies
2. Installs updated systemd units
3. Preserves your existing config, credentials, data
4. Runs `systemctl daemon-reload`
5. Restarts the bot if it was running

To see what changed before applying: `git log --oneline` or `git diff`.

---

## How it Works

### Cogs

The bot has four cogs that register as application (slash) commands:

| Cog | Purpose |
|-----|---------|
| **verify** | Verifies Discord users against Wild Apricot membership. Handles season re-verification (April), nickname sync, member role assignment (Social / Swabbie), and demotion enforcement for expired members. |
| **workhours** | `/workhours` — checks a member's submitted work hours from Google Sheets, aggregated by season (April 1 – March 31). |
| **roles** | Self-serve role assignment via reaction panels in #get-roles. Includes fleet, community, and waitlist roles. |
| **oops_something_broke** | Forum-based help-desk in the oops-something-broke channel. Tracks Pending/Complete status. |

### Systemd Services

| Service | Timer | Schedule | Purpose |
|---------|-------|----------|---------|
| blackbeard-bot | — | Always on | Discord bot (long-running) |
| blackbeard-backup | blackbeard-backup.timer | daily at 04:00 | Backup verified_members.json to Google Drive |

Both services log to journald:

```bash
journalctl -u blackbeard-bot -f
journalctl -u blackbeard-backup --since yesterday
```

### Configuration

Set these in `/etc/default/blackbeard-bot`:

| Variable | Purpose |
|----------|---------|
| `DISCORD_TOKEN` | Discord bot token (required) |
| `WA_API_KEY` | Wild Apricot API key (required) |
| `WA_ACCOUNT_ID` | Wild Apricot account ID (required) |
| `GOOGLE_SPREADSHEET_ID` | Google Sheet ID for workhours |
| `GOOGLE_SERVICE_ACCOUNT_JSON` | Path or JSON string of Google service account |
| `GOOGLE_DRIVE_FOLDER_ID` | Google Drive folder for backups |
| `GOOGLE_CLIENT_SECRET` | Path to GDrive OAuth client secret |
| `WORKHOURS_SHEET_NAME` | Sheet tab name for workhours (default: `Form Responses 1`) |
| `VERIFY_CHANNEL_NAME` | Discord channel for verification (default: `get-verified`) |
| `GET_ROLES_CHANNEL_NAME` | Discord channel for role panels (default: `get-roles`) |
| `ROLE_SOCIAL` | Name of the social role (default: `social`) |
| `ROLE_SWABBIE` | Name of the swabbie role (default: `Swabbie`) |
| `VERIFY_MESSAGE_STATE_FILE` | Path for verify message state JSON |
| `ROLE_PANEL_STATE_FILE` | Path for role panel state JSON |
| `VERIFIED_MEMBERS_FILE` | Path for verified members JSON |
| `DATA_DIR` | Where data files live (default: data/) |

### Data Persistence

Runtime data files (`verify_message.json`, `role_panels.json`, `verified_members.json`)
live in the `data/` directory, which should be a symlink to `/var/lib/blackbeard-bot/data/`.
The Makefile creates this symlink on `make install`.

- `make uninstall` preserves all data and credentials.
- `make purge` removes everything including data and credentials.

### Backup

The daily backup script (`scripts/upload_backup.py`) uploads `verified_members.json`
to Google Drive using OAuth. On first run, it opens an OAuth flow to create a cached
token. Subsequent runs use the cached token.

The default Google Drive folder ID is set in `config/default.env` and can be overridden.

### Prerequisites

- Python 3.10+
- systemd
- Network access to:
  - Discord API
  - Wild Apricot API
  - Google Sheets API
  - Google Drive API

### Repo Structure

```
├── Makefile              # install, build-install, uninstall, purge
├── config.py             # App configuration (reads from env)
├── main.py               # Bot entry point
├── requirements.txt      # Pinned Python dependencies
├── config/
│   └── default.env       # Template for /etc/default/blackbeard-bot
├── cogs/
│   ├── verify.py         # Member verification via Wild Apricot
│   ├── roles.py          # Self-serve role panels
│   ├── workhours.py      # Work hour tracking
│   └── oops_something_broke.py  # Help-desk ticketing
├── systemd/
│   ├── blackbeard-bot.service      # Discord bot (always on)
│   ├── blackbeard-backup.service    # Backup oneshot
│   └── blackbeard-backup.timer      # Daily at 04:00
├── scripts/
│   ├── upload_backup.py   # Google Drive backup
│   └── discord_alert.py   # Cross-service alert helper
├── .venv/                 # Python virtual env (created by make install)
├── data/                  # Runtime state (symlink to /var/lib/)
└── .env_template.txt      # Legacy env template
```

### Security Notes

- Bot token and API keys go in `/etc/default/blackbeard-bot` (mode 0600).
- OAuth credentials for Google Drive go in `/etc/blackbeard-bot/credentials/`.
- No secrets are committed to git.
- `make uninstall` preserves credentials, data, and env overrides.
- `make purge` removes everything including credentials and data.

### License

MIT
