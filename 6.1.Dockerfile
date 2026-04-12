# The system version is limited by:
#  - lxml: Requires specific versions of libxml2==2.9.1 and libxslt==1.1.28
FROM debian:buster-slim

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive


# Install system packages
ARG TARGETARCH \
    ODOO_PKGS="fonts-liberation libpq-dev libjpeg-dev zlib1g-dev libssl-dev libc6-dev libxml2-dev libxslt1-dev libldap2-dev libsasl2-dev gsfonts fonts-urw-base35"

# hadolint ignore=SC2086
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    rm /etc/apt/sources.list; \
    echo "deb http://archive.debian.org/debian-security buster/updates main" >> /etc/apt/sources.list.d/buster.list; \
    echo "deb http://archive.debian.org/debian buster main" >> /etc/apt/sources.list.d/buster.list; \
    apt-get update && apt-get install -y --no-install-recommends \
        # Common
        fontconfig \
        ca-certificates \
        git \
        curl \
        # By Conf
        ${ODOO_PKGS} \
        # PyEnv
        build-essential \
        patch; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    fc-cache -fv;


# Create the runtime user
ARG USER_ODOO_UID=10000 \
    USER_ODOO_GID=10001

# hadolint ignore=SC2153
RUN set -eux; \
    groupadd --gid "${USER_ODOO_GID}" odoo; \
    useradd \
        --no-log-init \
        --home-dir /home/odoo \
        --uid "${USER_ODOO_UID}" \
        --gid "${USER_ODOO_GID}" \
        -s /bin/bash \
        odoo; \
    mkdir -p /home/odoo /etc/odoo /opt/odoo /var/lib/odoo/data; \
    chown -R odoo:odoo /home/odoo /opt/odoo /etc/odoo /var/lib/odoo;


# Change to runtime user
USER odoo


# Install & activate PyEnv
ARG ODOO_PYTHON_VERSION="2.7" \
    SYSTEM_PYTHON_VERSION="3.13"
ARG PYTHON_SYSTEM_BIN_NAME="python${SYSTEM_PYTHON_VERSION}" \
    PYTHON_ODOO_BIN_NAME="python${ODOO_PYTHON_VERSION}"
ENV PATH="/home/odoo/.pyenv/bin:/home/odoo/.pyenv/shims:$PATH" \
    PYENV_ROOT="/home/odoo/.pyenv" \
    PYENV_VIRTUALENV_DISABLE_PROMPT=1

RUN set -eux; \
    curl -fsSL https://pyenv.run | bash; \
    eval "$(pyenv init --path)"; \
    eval "$(pyenv init -)"; \
    eval "$(pyenv virtualenv-init -)"; \
    pyenv install "${SYSTEM_PYTHON_VERSION}" "${ODOO_PYTHON_VERSION}"; \
    pyenv global "${SYSTEM_PYTHON_VERSION}" "${ODOO_PYTHON_VERSION}"; \
    rm -rf ${PYENV_ROOT}/cache/*;


### SYSTEM PYTHON ENV
WORKDIR /home/odoo

# Install System PIP & Extra dependencies
RUN set -eux; \
    "$PYTHON_SYSTEM_BIN_NAME" -m venv /home/odoo/.venv; \
    . .venv/bin/activate; \
    pip install --no-cache-dir --upgrade pip; \
    pip install --no-cache-dir git-aggregator pyyaml psycopg2; \
    pip cache purge; \
    deactivate;


### ODOO PYTHON ENV
WORKDIR /opt/odoo

# Install Odoo PIP & Extra dependencies
ARG ODOO_EXTRA_PIP_PKGS="pyinotify" \
    PIP_SHA256="40ee07eac6674b8d60fce2bbabc148cf0e2f1408c167683f110fd608b8d6f416"

RUN set -eux; \
    curl -L -o get-pip.py "https://bootstrap.pypa.io/pip/${ODOO_PYTHON_VERSION}/get-pip.py"; \
    echo "${PIP_SHA256}  get-pip.py" | sha256sum -c -; \
    "$PYTHON_ODOO_BIN_NAME" get-pip.py; \
    rm -f get-pip.py; \
    "$PYTHON_ODOO_BIN_NAME" -m pip install --no-cache-dir --upgrade pip; \
    "$PYTHON_ODOO_BIN_NAME" -m pip install --no-cache-dir virtualenv; \
    "$PYTHON_ODOO_BIN_NAME" -m virtualenv /opt/odoo/.venv; \
    . .venv/bin/activate; \
    pip install --no-cache-dir ${ODOO_EXTRA_PIP_PKGS}; \
    pip cache purge; \
    deactivate;

# Install PyXML (used by python zsi package)
ARG PYXML_SHA256="ea97ec56e1c87464b548e633d5a2b170d2e2a369195fb2fb7cabb2b609a56009"

# hadolint ignore=DL3003
RUN set -eux; \
    curl -L -o PyXML.tar.gz https://github.com/actmd/PyXML/archive/refs/tags/0.8.4.tar.gz; \
    echo "${PYXML_SHA256}  PyXML.tar.gz" | sha256sum -c -; \
    tar -xzvf PyXML.tar.gz; \
    . .venv/bin/activate; \
    cd ./PyXML-0.8.4; \
    "$PYTHON_ODOO_BIN_NAME" setup.py build --with-xslt; \
    "$PYTHON_ODOO_BIN_NAME" setup.py install; \
    cd ..; \
    deactivate; \
    rm -f PyXML.tar.gz; \
    rm -rf ./PyXML-0.8.4;


# System Post-Configurations
USER root

COPY --chown=odoo:odoo recipes/6.1/requirements.txt /opt/odoo/requirements.txt
COPY docker-entrypoint.sh /usr/local/sbin/
COPY tools/exec_env.sh /usr/local/sbin/exec_env
COPY tools/isodoo_generate_config.py /usr/local/sbin/isodoo_generate_config
COPY tools/isodoo_create_addons_symlinks.py /usr/local/sbin/isodoo_create_addons_symlinks
COPY tools/isodoo_check_addons_dependencies.py /usr/local/sbin/isodoo_check_addons_dependencies
COPY tools/isodoo_auto_fill_external_dependencies.py /usr/local/sbin/isodoo_auto_fill_external_dependencies
COPY tools/wait_for_psql.py /usr/local/sbin/wait_for_psql
COPY tools/isodoo_auto_fill_repos.py /usr/local/sbin/isodoo_auto_fill_repos
COPY tools/isodoo_update_addons.sh /usr/local/sbin/isodoo_update_addons
RUN chmod +x \
    /usr/local/sbin/docker-entrypoint.sh \
    /usr/local/sbin/exec_env \
    /usr/local/sbin/isodoo_generate_config \
    /usr/local/sbin/isodoo_create_addons_symlinks \
    /usr/local/sbin/isodoo_check_addons_dependencies \
    /usr/local/sbin/isodoo_auto_fill_external_dependencies \
    /usr/local/sbin/isodoo_auto_fill_repos \
    /usr/local/sbin/isodoo_update_addons \
    /usr/local/sbin/wait_for_psql;


# Change to runtime user
USER odoo


# Install Odoo + Extras
ONBUILD ARG EXT_DEPS_OVERRIDES='' \
            ODOO_VERSION="6.1" \
            AUTO_DOWNLOAD_DEPENDENCIES=true
ONBUILD ENV LC_ALL="C.UTF-8" \
            LANG="C.UTF-8" \
            GIT_DEPTH_NORMAL=1 \
            GIT_DEPTH_MERGE=500 \
            EXT_DEPS_OVERRIDES="openid:python-openid,ldap:python-ldap,${EXT_DEPS_OVERRIDES}" \
            VERIFY_MISSING_MODULES=true \
            AUTO_FILL_REPOS=true \
            ODOO_VERSION="${ODOO_VERSION}" \
            OCONF__options__data_dir="/var/lib/odoo/data" \
            OCONF__options__addons_path="/var/lib/odoo/core,/var/lib/odoo/extra"

ONBUILD COPY --from=deps --chown=odoo:odoo apt.txt /opt/odoo/apt.txt
ONBUILD COPY --from=deps --chown=odoo:odoo pip.txt /opt/odoo/pip.txt
ONBUILD COPY --from=addons --chown=odoo:odoo repos.yaml /opt/odoo/repos.yaml
ONBUILD COPY --from=addons --chown=odoo:odoo addons.yaml /opt/odoo/addons.yaml

ONBUILD USER root

ONBUILD RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
            --mount=type=cache,target=/var/lib/apt,sharing=locked \
            set -ex; \
            apt-get update; \
            cat /opt/odoo/apt.txt | apt-get install -y --no-install-recommends; \
            apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
            apt-get clean; \
            rm -rf /var/lib/apt/lists/*;

ONBUILD USER odoo

ONBUILD WORKDIR /opt/odoo/git

ONBUILD RUN set -eux; \
            isodoo_update_addons; \
            . /home/odoo/.venv/bin/activate; \
            [ "$AUTO_DOWNLOAD_DEPENDENCIES" = true ] && isodoo_auto_fill_external_dependencies; \
            deactivate;

ONBUILD WORKDIR /opt/odoo

ONBUILD USER root

ONBUILD RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
            --mount=type=cache,target=/var/lib/apt,sharing=locked \
            set -ex; \
            apt-get update; \
            xargs -r apt-get install -y --no-install-recommends < /opt/odoo/apt.txt; \
            apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
            apt-get clean; \
            rm -rf /var/lib/apt/lists/*; \
            rm -rf /tmp/*;

ONBUILD USER odoo

ONBUILD WORKDIR /opt/odoo/git/odoo

# hadolint ignore=DL3042
ONBUILD RUN set -ex; \
            . /opt/odoo/.venv/bin/activate; \
            # Install Outdated dependencies
            git clone https://github.com/Infinite-Code/PyChart --depth=1; \
            cd PyChart; \
            python setup.py install; \
            cd ..; \
            rm -rf PyChart; \
            # Install OpenERP
            mv /opt/odoo/requirements.txt .;\
            pip install --no-binary psycopg2 -r requirements.txt; \
            python setup.py install; \
            pip install -r /opt/odoo/pip.txt; \
            # Cleanup
            pip cache purge; \
            find .. -maxdepth 3 -name "build" -type d -exec rm -rf {} +; \
            find .. -name "*.egg-info" -type d -exec rm -rf {} +; \
            find .. -name "*.pyc" -type f -delete; \
            rm -rf /tmp/*; \
            # Post-configurations
            python -m compileall /var/lib/odoo/core; \
            python -m compileall /var/lib/odoo/extra; \
            ln -s /opt/odoo/.venv/bin/openerp-server /opt/odoo/.venv/bin/odoo; \
            chmod +x /opt/odoo/.venv/bin/odoo; \
            # Ensure all is working
            odoo --version; \
            deactivate;


ONBUILD WORKDIR /opt/odoo


# Expose Odoo services
EXPOSE 8069 8070 8071


# Run
ENTRYPOINT ["/usr/local/sbin/docker-entrypoint.sh"]
CMD ["odoo", "-c", "/etc/odoo/odoo.conf"]
