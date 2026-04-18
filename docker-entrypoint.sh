#!/bin/bash
set -e

# Enable NODE environment
[ -f "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"

# Use system python environment
. "/home/odoo/.venv/bin/activate"
echo "[entrypoint] ==== SYSTEM ENV. INFO ===="
INFO_ACTIVE_USER=$(whoami 2>&1)
INFO_ACTIVE_USER_ID=$(id -u 2>&1)
INFO_ACTIVE_USER_GID=$(id -g 2>&1)
if [[ "$INFO_ACTIVE_USER_ID" == "0" ]]; then
    echo "[entrypoint] - WARNING: Running as root"
fi
echo "[entrypoint] - Active user: $INFO_ACTIVE_USER ($INFO_ACTIVE_USER_ID:$INFO_ACTIVE_USER_GID)"
INFO_PYTHON_VERSION=$(python --version 2>&1)
echo "[entrypoint] - Python version: $INFO_PYTHON_VERSION"
if [ -f "${NVM_DIR}/nvm.sh" ]; then
    INFO_NODE_VERSION=$(node --version 2>&1)
    echo "[entrypoint] - Node version: $INFO_NODE_VERSION"
fi
if command -v wkhtmltopdf >/dev/null 2>&1; then
    INFO_WKHTMLTOPDF_VERSION=$(wkhtmltopdf --version 2>&1)
    echo "[entrypoint] - WKHTMLTOPDF version: $INFO_WKHTMLTOPDF_VERSION"
fi
echo "[entrypoint] ==== END SYSTEM INFO ===="
echo "[entrypoint] Generating Odoo configuration..."
if [[ -n "${ODOO_RC:-}" ]]; then
    CONFIG="$ODOO_RC"
elif [[ -n "${OPENERP_SERVER:-}" ]]; then
    CONFIG="$OPENERP_SERVER"
else
    echo "[entrypoint] No configuration defined! Fallback to 'auto' mode..."
    CONFIG="/etc/odoo/odoo.auto.conf"
    export ODOO_RC="$CONFIG"
    export OPENERP_SERVER="$CONFIG"
fi
if [[ $CONFIG == "/etc/odoo/odoo.auto.conf" ]]; then
    isodoo_generate_config "$CONFIG"
fi
RAW_ODOO_INFO=$(python3 -c "
import configparser
c = configparser.ConfigParser()
if not c.read('${CONFIG}'):
    exit(1)
opts = c['options']
print(f\"{opts.get('db_host', 'localhost')}|{opts.get('db_port', '5432')}|{opts.get('db_user', 'odoo')}|{opts['db_password']}\")
" 2>/dev/null)
if [[ -z "$RAW_ODOO_INFO" ]]; then
    echo "[ERROR] Could not read configuration or missing db_password in $CONFIG"
    exit 1
fi
IFS='|' read -ra odoo_db_info <<< "$RAW_ODOO_INFO"
echo "[entrypoint] Waiting for postgres database at ${odoo_db_info[0]}..."
wait_for_psql --db_host="${odoo_db_info[0]}" --db_port="${odoo_db_info[1]}" --db_user="${odoo_db_info[2]}" --db_password="${odoo_db_info[3]}" --timeout="${PSQL_WAIT_TIMEOUT:-30}"
deactivate

# Use odoo python environment
. /opt/odoo/.venv/bin/activate
echo "[entrypoint] ==== ODOO ENV. INFO ===="
echo "[entrypoint] - Odoo config: $CONFIG"
if [ -d /opt/odoo/git/odoo ]; then
    INFO_ODOO_SRC_HASH=$(git -C /opt/odoo/git/odoo rev-parse HEAD 2>/dev/null || echo "UNKNOWN")
    echo "[entrypoint] - Odoo source hash: $INFO_ODOO_SRC_HASH"
else
    echo "[entrypoint] - Odoo source hash: NO SOURCE DETECTED!"
fi
INFO_PYTHON_VERSION=$(python --version 2>&1)
echo "[entrypoint] - Python version: $INFO_PYTHON_VERSION"
echo "[entrypoint] ==== END ODOO INFO ===="

# Support OpenERP Web 6.0
if [ -f /etc/odoo/openerp-web.cfg ] && [ "$1" == "odoo" ]; then
    echo "[entrypoint] Starting Odoo Web..."
    openerp-web -c /etc/odoo/openerp-web.cfg &
fi
echo "[entrypoint] Starting..."
exec "$@"
