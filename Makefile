# BlackbeardBot build/deploy system
#
# The repo must be cloned to /opt/blackbeard-bot/ so that git pull
# updates everything in place.
#
# Update flow:
#   cd /opt/blackbeard-bot && sudo make build-install
#
# This creates/updates the venv, installs systemd units, reloads
# systemd, and restarts the bot.

BOT_DIR := /opt/blackbeard-bot
SYSTEMD_DIR := /etc/systemd/system
CONFIG_DIR := /etc/blackbeard-bot
CRED_DIR := $(CONFIG_DIR)/credentials
DATA_DIR := /var/lib/blackbeard-bot/data
ENV_FILE := /etc/default/blackbeard-bot
VENV := .venv

.PHONY: all install build-install uninstall purge restart restart-bot

all: install

# === VENV SETUP ===

.venv:
	python3 -m venv "$(VENV)"
	"$(VENV)/bin/pip" install --upgrade pip setuptools wheel
	"$(VENV)/bin/pip" install -r requirements.txt

venv: .venv

# === INSTALL (idempotent) ===

install: .venv
	@echo "=== Installing BlackbeardBot ==="

	@# Create system directories
	mkdir -p $(DATA_DIR) $(CONFIG_DIR) $(CRED_DIR)

	@# Create/update env file (preserves existing)
	if [ ! -f $(ENV_FILE) ]; then \
		install -m 644 config/default.env $(ENV_FILE); \
	else \
		install -m 644 config/default.env $(ENV_FILE).default; \
	fi

	@# Install systemd units
	install -m 644 systemd/blackbeard-bot.service $(SYSTEMD_DIR)/
	install -m 644 systemd/blackbeard-backup.service $(SYSTEMD_DIR)/
	install -m 644 systemd/blackbeard-backup.timer $(SYSTEMD_DIR)/
	systemctl daemon-reload

	@# Ensure bot's data directory has a symlink from repo to /var/lib
	@if [ ! -L data ] && [ ! -d data ]; then \
		ln -s $(DATA_DIR) data; \
	elif [ -d data ] && [ ! -L data ]; then \
		echo "WARNING: data/ is a real directory. Move contents to $(DATA_DIR) and replace with symlink."; \
	fi

	@# Restart bot if it was running
	if systemctl is-active -q blackbeard-bot 2>/dev/null; then \
		echo "  Restarting blackbeard-bot..."; \
		systemctl restart blackbeard-bot; \
	fi

	@# Restart backup timer if it was enabled
	if systemctl is-enabled -q blackbeard-backup.timer 2>/dev/null; then \
		systemctl restart blackbeard-backup.timer; \
	fi

	@echo ""
	@echo "=== Installation complete ==="
	@echo ""
	@echo "Review and set up:"
	@echo "  1. Credentials in $(CRED_DIR)/"
	@echo "     - google_credentials.json    (Google service account)"
	@echo "     - gdrive_client_secret.json  (Google Drive OAuth)"
	@echo "  2. Set secrets in $(ENV_FILE)"
	@echo "     - DISCORD_TOKEN"
	@echo "     - WA_API_KEY"
	@echo "     - WA_ACCOUNT_ID"
	@echo "     - GOOGLE_SPREADSHEET_ID"
	@echo "     - GOOGLE_SERVICE_ACCOUNT_JSON    (default: $(CRED_DIR)/google_credentials.json)"
	@echo "     - GOOGLE_CLIENT_SECRET           (default: $(CRED_DIR)/gdrive_client_secret.json)"
	@echo "     - GOOGLE_DRIVE_FOLDER_ID"
	@echo "  3. Edit $(ENV_FILE) for other env overrides"
	@echo ""
	@echo "Enable services:"
	@echo "     sudo systemctl enable --now blackbeard-bot"
	@echo "     sudo systemctl enable --now blackbeard-backup.timer"

# === BUILD-INSTALL (one-liner for updates, assumes git pull already done) ===

build-install:
	$(MAKE) install

# === UNINSTALL (preserves credentials + data) ===

uninstall:
	@echo "Stopping services..."
	-systemctl stop blackbeard-bot 2>/dev/null
	-systemctl stop blackbeard-backup.timer 2>/dev/null
	@echo "Removing systemd units..."
	-rm -f $(SYSTEMD_DIR)/blackbeard-bot.service
	-rm -f $(SYSTEMD_DIR)/blackbeard-backup.service
	-rm -f $(SYSTEMD_DIR)/blackbeard-backup.timer
	systemctl daemon-reload
	@echo "Removing venv..."
	-rm -rf $(VENV)
	@echo "Preserved:"
	@echo "  $(CONFIG_DIR)/  (config untouched)"
	@echo "  $(CRED_DIR)/    (credentials untouched)"
	@echo "  $(DATA_DIR)/    (data untouched)"
	@echo "  $(ENV_FILE)"
	@echo "Uninstall complete."

# === PURGE (full removal including credentials + data) ===

purge: uninstall
	@echo "Removing configuration and data..."
	-rm -rf $(CONFIG_DIR)
	-rm -f $(ENV_FILE)
	-rm -rf $(DATA_DIR)
	@echo "Purge complete."

# === UTILITY ===

restart-bot:
	systemctl restart blackbeard-bot