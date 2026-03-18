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
isodoo_generate_config /etc/odoo/odoo.conf
echo "[entrypoint] Waiting for postgres database..."
wait_for_psql --db_host="$OCONF__options__db_host" --db_port="${OCONF__options__db_port:-5432}" --db_user="${OCONF__options__db_user}" --db_password="${OCONF__options__db_password}" --timeout=30
deactivate

# Use odoo python environment
. /opt/odoo/.venv/bin/activate
echo "[entrypoint] ==== ODOO ENV. INFO ===="
if [ -d /opt/odoo/git/odoo ]; then
    INFO_ODOO_SRC_HASH=$(git -C /opt/odoo/git/odoo rev-parse HEAD 2>&1)
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
