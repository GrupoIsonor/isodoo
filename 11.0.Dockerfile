# The system version is limited by:
#  - WKHTMLTOPDF: requires libssl1.1
FROM debian:buster-slim

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive


# Install system packages
ARG TARGETARCH \
    WKHTMLTOPDF_PKGS="libfreetype6 libjpeg62-turbo libpng16-16 libxcb1 libxext6 libxrender1 xfonts-75dpi xfonts-base" \
    ODOO_PKGS="fonts-liberation libpq-dev libjpeg-dev zlib1g-dev libssl-dev libc6-dev libxml2-dev libxslt1-dev libldap2-dev libsasl2-dev"

# hadolint ignore=SC2086
RUN set -eux; \
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
        ${WKHTMLTOPDF_PKGS} \
        ${ODOO_PKGS} \
        # PyEnv
        build-essential \
        patch; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    fc-cache -fv;


# Install WKHTMLTOX
ARG WKHTMLTOPDF_VERSION="0.12.1.4-2" \
    WKHTMLTOPDF_BASE_DEBIAN_VER=buster

RUN set -eux; \
    curl -L -o wkhtmltox.deb "https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOPDF_VERSION}/wkhtmltox_${WKHTMLTOPDF_VERSION}.${WKHTMLTOPDF_BASE_DEBIAN_VER}_${TARGETARCH}.deb"; \
    apt-get install --no-install-recommends -y ./wkhtmltox.deb; \
    rm wkhtmltox.deb;


# Create the runtime user
ARG USER_ODOO_UID=7777 \
    USER_ODOO_GID=7777

# hadolint ignore=SC2153
RUN set -eux; \
    groupadd --gid "${USER_ODOO_GID}" --system odoo; \
    useradd \
        --home-dir /home/odoo \
        --system \
        --uid "${USER_ODOO_UID}" \
        --gid "${USER_ODOO_GID}" \
        -s /bin/bash \
        odoo; \
    mkdir -p /home/odoo /etc/odoo /opt/odoo /var/lib/odoo/data; \
    chown -R odoo:odoo /home/odoo /opt/odoo /etc/odoo /var/lib/odoo;


# Change to runtime user
USER odoo


# Install NodeJS & Depedencies
ARG NVM_VERSION="v0.40.3" \
    NODE_VERSION="6.17.1" \
    ODOO_NPM_PKGS="rtlcss less@3.10.3 less-plugin-clean-css"

# hadolint ignore=SC2086
RUN set -ex; \
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash; \
    . ~/.nvm/nvm.sh; \
    nvm install "${NODE_VERSION}"; \
    nvm use "${NODE_VERSION}"; \
    npm install -g ${ODOO_NPM_PKGS};


# Install & activate PyEnv
ARG ODOO_PYTHON_VERSION="3.7" \
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
    "$PYTHON_SYSTEM_BIN_NAME" -m venv ~/.venv; \
    . .venv/bin/activate; \
    pip install --no-cache-dir --upgrade pip; \
    pip install --no-cache-dir click-odoo-contrib git-aggregator pyyaml psycopg2; \
    pip cache purge; \
    deactivate;


### ODOO PYTHON ENV
WORKDIR /opt/odoo

# Install Odoo PIP & Extra dependencies
RUN set -eux; \
    curl -L -o get-pip.py "https://bootstrap.pypa.io/pip/${ODOO_PYTHON_VERSION}/get-pip.py"; \
    "$PYTHON_ODOO_BIN_NAME" get-pip.py; \
    rm -f get-pip.py; \
    "$PYTHON_ODOO_BIN_NAME" -m pip install --no-cache-dir --upgrade pip; \
    "$PYTHON_ODOO_BIN_NAME" -m pip install --no-cache-dir virtualenv; \
    "$PYTHON_ODOO_BIN_NAME" -m virtualenv /opt/odoo/.venv;


# System Post-Configurations
USER root

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


# Verifications
RUN set -ex; \
    . ~/.nvm/nvm.sh; \
    wkhtmltopdf --version; \
    node --version;


# Install Odoo + Extras
ONBUILD ARG EXT_DEPS_OVERRIDES='' \
            ODOO_VERSION="11.0" \
            AUTO_DOWNLOAD_DEPENDENCIES=true
ONBUILD ENV LC_ALL="C.UTF-8" \
            LANG="C.UTF-8" \
            GIT_DEPTH_NORMAL=1 \
            GIT_DEPTH_MERGE=500 \
            EXT_DEPS_OVERRIDES="ldap:python-ldap,usb.core:pyusb,${EXT_DEPS_OVERRIDES}" \
            VERIFY_MISSING_MODULES=true \
            AUTO_FILL_REPOS=true \
            ODOO_VERSION="${ODOO_VERSION}" \
            OCONF__options__data_dir="/var/lib/odoo/data" \
            OCONF__options__addons_path="/var/lib/odoo/core,/var/lib/odoo/extra"

ONBUILD COPY --from=deps --chown=odoo:odoo apt.txt /opt/odoo/apt.txt
ONBUILD COPY --from=deps --chown=odoo:odoo pip.txt /opt/odoo/pip.txt
ONBUILD COPY --from=deps --chown=odoo:odoo npm.txt /opt/odoo/npm.txt
ONBUILD COPY --from=addons --chown=odoo:odoo repos.yaml /opt/odoo/repos.yaml
ONBUILD COPY --from=addons --chown=odoo:odoo addons.yaml /opt/odoo/addons.yaml

ONBUILD USER odoo

ONBUILD WORKDIR /opt/odoo/git

ONBUILD RUN set -ex; \
            isodoo_update_addons; \
            . ~/.venv/bin/activate; \
            [ "$AUTO_DOWNLOAD_DEPENDENCIES" = true ] && isodoo_auto_fill_external_dependencies; \
            deactivate;

ONBUILD WORKDIR /opt/odoo

ONBUILD RUN set -ex; \
            . ~/.nvm/nvm.sh; \
            xargs -r npm install -g < /opt/odoo/npm.txt;

ONBUILD USER root

ONBUILD RUN set -ex; \
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
            printf '#!/bin/bash\n/opt/odoo/git/odoo/odoo-bin "$@"' > /opt/odoo/.venv/bin/odoo; \
            chmod +x /opt/odoo/.venv/bin/odoo; \
            # Hard-Change pinned versions
            sed -i \
                -e '/^pytz==/c\pytz>=2025.2' \
                requirements.txt; \
            pip install --no-binary psycopg2 -r requirements.txt; \
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
            # Ensure all is working
            odoo --version; \
            deactivate;


ONBUILD WORKDIR /opt/odoo


# Expose Odoo services
EXPOSE 8069 8071 8072


# Run
ENTRYPOINT ["/usr/local/sbin/docker-entrypoint.sh"]
CMD ["odoo", "-c", "/etc/odoo/odoo.conf"]
