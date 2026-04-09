<h1 align="center">
  <div>isOdoo - Container Image</div>

[![Tests](https://github.com/GrupoIsonor/isOdoo/actions/workflows/isodoo.yml/badge.svg)](https://github.com/GrupoIsonor/isOdoo/actions/workflows/isodoo.yml)

</h1>

<p align="center">
ISO 0doo (By <a src="https://www.grupoisonor.es/">Grupo Isonor</a>)
</p>
<p align="center">
*** PROJECT UNDER DEVELOPMENT. NOT READY FOR PRODUCTION ***

A lightweight image for running [Odoo CE](https://www.odoo.com/) from 6.0 to the moon! Strongly inspired by the [Doodba project](https://github.com/Tecnativa/doodba/) and the official [Odoo image](https://github.com/odoo/docker).
</p>

---

## :ballot_box_with_check: Features

- Installation from source code
- Detect missing modules at build time
- Automatically obtains and downloads modules external dependencies
- Strong use of virtual environments (using [uv](https://docs.astral.sh/uv/) in 14.0+)
- [click-odoo-contrib](https://github.com/acsone/click-odoo-contrib)
- [git-aggregator](https://github.com/acsone/git-aggregator)
- Compatible with [podman](https://podman.io/) (using --format docker)

## :page_facing_up: Documentation

To configure Odoo, simply use environment variables with the prefix ```OCONF__{section}__{Param Name}```. Example for changing workers: ```OCONF__options__workers=4```.

** On Odoo 6.x you can use environment variables with the prefix ```OWCONF__{section}__{Param Name}``` (taking into account that the underscores will be replaced by dots).

### Build Arguments

| Name | Description |
|----------------|-------------|
| WKHTMLTOPDF_PKGS | System packages required to use WKHTMLTOPDF |
| ODOO_PKGS | System packages required to use Odoo |
| WKHTMLTOPDF_VERSION | Version of WKHTMLTOPDF to install |
| WKHTMLTOPDF_BASE_DEBIAN_VER | WKHTMLTOPDF system version to install |
| USER_ODOO_UID | Odoo user ID |
| USER_ODOO_GID | Odoo user GID |
| NVM_VERSION | NVM version to use |
| NODE_VERSION | Node version to install |
| ODOO_NPM_PKGS | Node packages required to use Odoo |
| ODOO_PYTHON_VERSION | Python version to install for Odoo |
| SYSTEM_PYTHON_VERSION| Python version to install for the system |

### -ONBUILD- Build Arguments

| Name | Description |
|----------------|-------------|
| EXT_DEPS_OVERRIDES | Overrides for the module external dependency names (old_name:new_name) separated by commas (Only useful if AUTO_DOWNLOAD_DEPENDENCIES is used) |
| ODOO_VERSION | Version of Odoo to install |
| AUTO_DOWNLOAD_DEPENDENCIES | Indicates whether all external dependencies of the available modules must be downloaded |

### -ONBUILD- Environment Variables

| Name | Description | Required | Default |
|----------------|-------------|-------------|-------------|
| GITHUB_TOKEN | User token to use with git-aggregator | No | "" |
| GIT_DEPTH_NORMAL | Default depth of commits | Yes | 1 |
| GIT_DEPTH_MERGE | Default depth of commits when cloning with merges | Yes | 500 |
| EXT_DEPS_OVERRIDES | Overrides for the dependency names (old_name:new_name) separated by commas (Only useful if AUTO_DOWNLOAD_DEPENDENCIES is used) | No | "" |
| VERIFY_MISSING_MODULES | Indicates whether all modules (and other modules on which it depends) are available | No | True |
| AUTO_FILL_REPOS | Indicates whether repos.yaml should be adjusted to match what is used in addons.yaml (OCA repositories only) | No | True |
| PSQL_WAIT_TIMEOUT | Timeout to wait for the database | No | 30 |

** Check the Dockerfile for more configuration variables/args.

### Additional Context

| Name | Content | Required | Description |
|----------------|-------------|-------------|------------- |
| deps | apt.txt - pip.txt - npm.txt | Yes | Contains the files that define the necessary dependencies |
| addons | repos.yaml - addons.yaml | Yes | Contains the files that define the available add-ons |
| private | add-ons folders | No | Contains the private add-ons |

** Example: https://github.com/GrupoIsonor/isodoo/tree/master/tests/data/project_demo/v19.0

### Default Ports

| Port | Odoo Version |Description |
|----------------|-------------|-------------|
| 8069 | 6.1+ | Default port for HTTP and XML-RPC (web interface and API) |
| 8071 | 6.0+ | **Optional** port for XML-RPC (depends on configuration) |
| 8072 | 6.0+ | Port for long polling (real-time notifications, such as chat) |
| 8080 | 6.0 | [6.0 Only] Default port for HTTP and XML-RPC (web interface and API) |

---
<div align="center"><h2>Very Basic Usage Example</h2></div>

### Folder Tree
```
myproject/
  - Dockerfile
  - docker-compose.yaml
  - deps/
    - pip.txt
    - apt.txt
    - npm.txt
  - addons/
    - addons.yaml
    - repos.yaml
  - private/
    - my_module_a/
    - my_module_b/
```

### Dockerfile
```Dockerfile
ARG ODOO_VERSION
FROM ghcr.io/grupoisonor/isodoo:${ODOO_VERSION} AS isodoo-runtime
FROM isodoo-runtime AS isodoo-runtime-private
COPY --from=private --chown=odoo:odoo / /var/lib/odoo/private
ENV OCONF__options__addons_path="${OCONF__options__addons_path},/var/lib/odoo/private"
```

### docker-compose.yaml
```yml
services:
  odoo:
    build:
      context: .
      args:
        ODOO_VERSION: 19.0
      additional_contexts:
        deps: ./deps
        addons: ./addons
        private: ./private
    depends_on:
      db:
        condition: service_healthy
    ports:
      - '127.0.0.1:8069:8069'
    environment:
      OCONF__options__log_level: debug
      OCONF__options__db_filter: odoodb$
      OCONF__options__db_user: odoo
      OCONF__options__db_password: odoo
      OCONF__options__db_host: odoo-db
      OCONF__options__db_name: odoodb
      OCONF__options__proxy_mode: false
    volumes:
      - filestore:/var/lib/odoo/data
    hostname: odoo

  db:
    image: postgres:18.0-alpine
    environment:
      POSTGRES_DB: odoodb
      POSTGRES_PASSWORD: odoo
      POSTGRES_USER: odoo
      POSTGRES_INITDB_ARGS: --locale=C --encoding=UTF8
    volumes:
      - db:/var/lib/postgresql
    hostname: odoo-db
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U odoo -d odoodb"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s


volumes:
  filestore:
  db:
```
