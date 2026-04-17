ARG ODOO_VERSION
FROM localhost/test:docker-isodoo-${ODOO_VERSION} AS isodoo-runtime
FROM isodoo-runtime AS isodoo-runtime-private
# hadolint ignore=DL3022
COPY --from=private --chown=odoo:odoo / /var/lib/odoo/private
ENV OCONF__options__addons_path="/var/lib/odoo/private,${OCONF__options__addons_path}"
