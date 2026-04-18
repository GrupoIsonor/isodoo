# Copyright  Alexandre Díaz <dev@redneboa.es>
import requests
from conftest import OLDER_VERSIONS

ISODOO_UV_MIN_VERSION = 14
OPENERP_VERSIONS = ("6.0", "6.1", "7.0")
# <odoo version>: (<repo name>, <module_name>, (<list pip deps>, <list apt deps>))
# See data/project_demo/v<odoo version>/addons/addons.yaml for more details
EXTRA_ADDONS = {
    "6.0": ("l10n-spain", "city", None),
    "6.1": ("reporting-engine", "report_xls", (("xlwt",), None)),
    "7.0": ("reporting-engine", "report_xls", (("xlwt",), None)),
    "8.0": ("reporting-engine", "report_xlsx", (("xlsxwriter",), None)),
    "9.0": ("reporting-engine", "report_xlsx", (("xlsxwriter",), None)),
    "10.0": ("reporting-engine", "report_xlsx", (("xlsxwriter",), None)),
    "11.0": ("reporting-engine", "report_xlsx", (("xlsxwriter",), None)),
    "12.0": ("reporting-engine", "report_xlsx", (("xlsxwriter",), None)),
    "13.0": (
        "reporting-engine",
        "report_xlsx_boilerplate",
        (
            (
                "xlsxwriter",
                "openpyxl",
            ),
            None,
        ),
    ),
    "14.0": ("reporting-engine", "report_fillpdf", (("fdfgen",), ("pdftk",))),
    "15.0": ("reporting-engine", "report_xlsx", (("xlsxwriter", "xlrd"), None)),
    "16.0": ("reporting-engine", "sql_export_excel", (("openpyxl",), None)),
    "17.0": ("reporting-engine", "sql_export_excel", (("openpyxl",), None)),
    "18.0": ("reporting-engine", "sql_export_excel", (("openpyxl",), None)),
    "19.0": ("reporting-engine", "report_xlsx", (("xlsxwriter", "xlrd"), None)),
}


class TestIsOdooContainer:
    def test_odoo_version(self, exec_docker, env_info):
        version = exec_docker("odoo", ["odoo", "--version"])
        assert env_info["options"]["odoo_version"] in version

    def test_odoo_pip_dependencies(self, exec_docker, env_info):
        odoo_ver = env_info["options"]["odoo_version"]
        odoo_major_ver = int(odoo_ver.split(".", 1)[0])
        pip_info = exec_docker("odoo", ["cat", "/opt/odoo/pip.txt"])
        assert "test-pip-install" in pip_info
        if odoo_major_ver < ISODOO_UV_MIN_VERSION:
            pip_info = exec_docker("odoo", ["pip", "show", "pip"])
            assert pip_info and "not found" not in pip_info
            pip_info = exec_docker("odoo", ["pip", "show", "test-pip-install"])
            assert pip_info and "not found" not in pip_info
            pip_info = exec_docker("odoo", ["pip", "show", "invented1234"])
            assert "not found" in pip_info
        else:
            pip_info = exec_docker("odoo", ["uv", "pip", "show", "pytz"])
            assert pip_info and "not found" not in pip_info
            pip_info = exec_docker("odoo", ["uv", "pip", "show", "test-pip-install"])
            assert pip_info and "not found" not in pip_info
            pip_info = exec_docker("odoo", ["uv", "pip", "show", "invented1234"])
            assert "not found" in pip_info

    def test_odoo_apt_dependencies(self, exec_docker):
        apt_info = exec_docker("odoo", ["cat", "/opt/odoo/apt.txt"])
        assert "hello" in apt_info
        apt_info = exec_docker("odoo", ["dpkg-query", "-W", "-f='${Status}\n'", "apt"])
        assert "ok installed" in apt_info
        apt_info = exec_docker(
            "odoo", ["dpkg-query", "-W", "-f='${Status}\n'", "hello"]
        )
        assert "ok installed" in apt_info
        apt_info = exec_docker(
            "odoo", ["dpkg-query", "-W", "-f='${Status}\n'", "invented1234"]
        )
        assert "no packages found" in apt_info

    def test_odoo_npm_dependencies(self, exec_docker, env_info):
        odoo_ver = env_info["options"]["odoo_version"]
        if odoo_ver in OPENERP_VERSIONS:
            return None
        npm_info = exec_docker("odoo", ["cat", "/opt/odoo/npm.txt"])
        assert "mirlo" in npm_info
        npm_info = exec_docker("odoo", ["npm", "ls", "-g"])
        assert "npm" in npm_info
        assert "mirlo" in npm_info
        assert npm_info and "invented1234" not in npm_info

    def test_odoo_repos(self, exec_docker):
        repo_info = exec_docker("odoo", ["cat", "/opt/odoo/repos.auto.yaml"])
        assert "odoo" in repo_info
        repo_info = exec_docker("odoo", ["ls", "/var/lib/odoo/core"])
        assert repo_info and "cannot access" not in repo_info
        assert "account" in repo_info

    def test_odoo_extra_addons(self, exec_docker, env_info):
        odoo_ver = env_info["options"]["odoo_version"]
        addon_info = EXTRA_ADDONS[odoo_ver]
        repo_info = exec_docker("odoo", ["cat", "/opt/odoo/repos.auto.yaml"])
        assert addon_info[0] in repo_info
        repo_info = exec_docker("odoo", ["ls", "/var/lib/odoo/extra"])
        assert repo_info and "cannot access" not in repo_info
        assert addon_info[1] in repo_info

    def test_odoo_private_addons(self, exec_docker, install_module, env_info):
        odoo_ver = env_info["options"]["odoo_version"]
        odoo_major_ver = int(odoo_ver.split(".", 1)[0])
        addons_info = exec_docker("odoo", ["ls", "/var/lib/odoo/private"])
        assert addons_info and "cannot access" not in addons_info
        assert "demo_addon" in addons_info
        addons_info = install_module("invented1234")
        assert "ignored: invented1234" in addons_info
        addons_info = install_module("demo_addon")
        check_msg = (
            "demo_addon: creating or updating"
            if odoo_major_ver < 14
            else "demo_addon loaded"
        )
        assert check_msg in addons_info

    def test_odoo_config(self, exec_docker):
        config_info = exec_docker("odoo", ["cat", "/etc/odoo/odoo.auto.conf"])
        assert "db_name = odoodb" in config_info

    def test_auto_download(self, exec_docker, env_info):
        odoo_ver = env_info["options"]["odoo_version"]
        addon_info = EXTRA_ADDONS[odoo_ver]
        if not addon_info[2]:
            return None
        odoo_major_ver = int(odoo_ver.split(".", 1)[0])
        # pyhton
        cat_info = exec_docker("odoo", ["cat", "/opt/odoo/pip.txt"])
        pip_deps = addon_info[2][0]
        if pip_deps:
            for pip_dep in pip_deps:
                assert pip_dep in cat_info
                if odoo_major_ver < ISODOO_UV_MIN_VERSION:
                    pip_info = exec_docker("odoo", ["pip", "show", pip_dep])
                    assert pip_info and "not found" not in pip_info
                else:
                    pip_info = exec_docker("odoo", ["uv", "pip", "show", pip_dep])
                    assert pip_info and "not found" not in pip_info
        # apt
        cat_info = exec_docker("odoo", ["cat", "/opt/odoo/apt.txt"])
        apt_deps = addon_info[2][1]
        if apt_deps:
            for apt_dep in apt_deps:
                assert apt_dep in cat_info
                apt_info = exec_docker(
                    "odoo", ["dpkg-query", "-W", "-f='${Status}\n'", apt_dep]
                )
                assert "ok installed" in apt_info

    def test_simple_http(self, docker_env, env_info):
        odoo_ver = env_info["options"]["odoo_version"]
        if odoo_ver in OPENERP_VERSIONS:
            get_url = f"http://{env_info['ip']}:{env_info['ports']['odoo']}"
        else:
            get_url = f"http://{env_info['ip']}:{env_info['ports']['odoo']}/web/login"
        resp = requests.get(get_url)
        assert resp.status_code == 200
        projname = (
            "openerp"
            if env_info["options"]["odoo_version"] in OPENERP_VERSIONS
            else "Odoo"
        )
        assert projname in resp.text

    def test_click_odoo(self, exec_docker, env_info):
        odoo_version = env_info["options"]["odoo_version"]
        if odoo_version in OLDER_VERSIONS:
            return

        user_login = exec_docker(
            "odoo",
            ["click-odoo"],
            stdin="ulogin=env['res.users'].browse(1).login;print('isodoo ok test' if ulogin else 'isodoo failed test')",
        )
        assert "isodoo ok test" in user_login

    def test_click_odoo_contrib(self, exec_docker, env_info):
        odoo_version = env_info["options"]["odoo_version"]
        if odoo_version in OLDER_VERSIONS:
            return

        result = exec_docker(
            "odoo",
            [
                "click-odoo-makepot",
                "--addons-dir",
                "/var/lib/odoo/extra",
                "--msgmerge",
                "--no-fuzzy-matching",
                "--purge-old-translations",
            ],
        )
        assert "not found" not in result
