# Copyright  Alexandre Díaz <dev@redneboa.es>
import os
import time
import pytest
import shutil
import subprocess
from pathlib import Path
from python_on_whales import DockerClient

IMAGE_TAG_NAME = "localhost/test:docker-isodoo"
COMPOSE_PROJECT_NAME = "isodoo-test"
PG_VERSIONS = {
    "6.0": "9.3",
    "6.1": "9.3",
    "7.0": "9.3",
    "8.0": "9.6",
    "9.0": "11",
    "10.0": "12",
    "11.0": "13",
    "12.0": "14",
    "13.0": "15",
    "14.0": "16",
    "15.0": "16",
    "16.0": "17",
    "17.0": "17",
    "18.0": "17",
    "19.0": "18",
}
OLDER_VERSIONS = ("6.0", "6.1", "7.0", "8.0", "9.0", "10.0")


def _podman_execute(service: str, command: list[str], tty: bool = False) -> str:
    podman_cmd = ["podman", "compose", "-p", COMPOSE_PROJECT_NAME, "exec"]

    if tty:
        podman_cmd.extend(["-it"])
    else:
        podman_cmd.append("-T")

    podman_cmd.append(service)
    podman_cmd.extend(command)

    result = subprocess.run(
        podman_cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )

    output = result.stdout

    clean_lines = [
        line
        for line in output.splitlines(keepends=True)
        if "The input device is not a TTY" not in line
    ]
    clean_output = "".join(clean_lines)

    return clean_output


def _podman_build(
    context_path,
    file=None,
    tags=None,
    cache=True,
    pull=True,
    build_args=None,
    extra_args=None,
):
    context_path = Path(context_path).resolve()
    if not context_path.is_dir():
        raise ValueError(f"Context path is not a valid directory: {context_path}")

    cmd = ["podman", "build", "--format", "docker"]

    if file:
        cmd.extend(["-f", str(Path(file).resolve())])

    if tags:
        if isinstance(tags, str):
            tags = [tags]
        for tag in tags:
            cmd.extend(["-t", tag])
    if not cache:
        cmd.append("--no-cache")
    if pull:
        cmd.append("--pull")

    if build_args:
        if isinstance(build_args, dict):
            for key, value in build_args.items():
                cmd.extend(["--build-arg", f"{key}={value}"])
        elif isinstance(build_args, str):
            cmd.extend(["--build-arg", build_args])
        else:
            for arg in build_args:
                cmd.extend(["--build-arg", str(arg)])

    if extra_args:
        cmd.extend(extra_args)

    cmd.append(str(context_path))

    try:
        subprocess.run(
            cmd,
            check=True,
            text=True,
            # Muestra salida en tiempo real (útil en CI / scripts largos)
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
    except subprocess.CalledProcessError as e:
        print("Error podman build:")
        print(e.output if e.output else "No detailed output.")
        raise


def _get_preferred_client_type():
    if shutil.which("podman"):
        return "podman"
    if shutil.which("docker"):
        return "docker"
    raise RuntimeError("Need install podman or docker (with compose)")


def _wait_for_odoo(ip_address, port):
    import requests
    from requests.exceptions import RequestException

    url = f"http://{ip_address}:{port}"
    for _ in range(300):
        try:
            r = requests.get(url, timeout=5)
            if r.status_code == 200:
                break
        except RequestException:
            pass
        time.sleep(2)
    else:
        raise TimeoutError("Odoo did not start on time")


def pytest_addoption(parser):
    parser.addoption("--no-cache", action="store_true", default=False)
    parser.addoption("--odoo-version", action="store", default="6.0")
    parser.addoption("--client-type", action="store", default=None)


@pytest.fixture(scope="session")
def env_info(pytestconfig):
    no_cache = bool(pytestconfig.getoption("no_cache", False))
    odoo_ver = pytestconfig.getoption("odoo_version")
    client_type = pytestconfig.getoption("client_type") or _get_preferred_client_type()
    odoo_port = "8080" if odoo_ver == "6.0" else "8069"

    return {
        "ip": "127.0.0.1",
        "ports": {
            "odoo": odoo_port,
        },
        "options": {
            "no_cache": no_cache,
            "odoo_version": odoo_ver,
        },
        "client_type": client_type,
    }


@pytest.fixture(scope="session")
def docker_env(env_info):
    odoo_ver = env_info["options"]["odoo_version"]
    os.environ["PYTEST_ODOO_VERSION"] = odoo_ver
    os.environ["PYTEST_PG_VERSION"] = PG_VERSIONS[odoo_ver]
    client_type = env_info["client_type"]
    client_call = [client_type]
    # isOdoo Base
    if client_type == "podman":
        os.environ["PODMAN_COMPOSE_PROVIDER"] = "/usr/bin/podman-compose"
        os.environ["PODMAN_COMPOSE_WARNING_LOGS"] = "false"
        _podman_build(
            ".",
            file=f"./{odoo_ver}.Dockerfile",
            tags=f"{IMAGE_TAG_NAME}-{odoo_ver}",
            cache=not env_info["options"]["no_cache"],
        )
    else:
        docker = DockerClient(client_call=client_call, client_type=client_type)
        docker.build(
            ".",
            file=f"./{odoo_ver}.Dockerfile",
            tags=f"{IMAGE_TAG_NAME}-{odoo_ver}",
            cache=not env_info["options"]["no_cache"],
        )

    os.chdir("./tests/data/project_demo")
    # isOdoo Runtime
    if client_type == "podman":
        _podman_build(
            ".",
            file=f"./Dockerfile",
            tags=f"{IMAGE_TAG_NAME}-demo-{odoo_ver}",
            cache=not env_info["options"]["no_cache"],
            build_args={
                "ODOO_VERSION": odoo_ver,
            },
            extra_args=[
                "--pull=never",
                "--build-context",
                f"deps=./v{odoo_ver}/deps",
                "--build-context",
                f"addons=./v{odoo_ver}/addons",
                "--build-context",
                f"private=./v{odoo_ver}/private",
            ],
        )
    else:
        docker = DockerClient(client_call=client_call, client_type=client_type)
        docker.build(
            ".",
            file=f"./Dockerfile",
            tags=f"{IMAGE_TAG_NAME}-demo-{odoo_ver}",
            cache=not env_info["options"]["no_cache"],
            build_args={
                "ODOO_VERSION": odoo_ver,
            },
            pull=False,
            build_contexts={
                "deps": f"./v{odoo_ver}/deps",
                "addons": f"./v{odoo_ver}/addons",
                "private": f"./v{odoo_ver}/private",
            },
        )

    docker = DockerClient(
        client_call=client_call,
        client_type=client_type,
        compose_files=["docker-compose.yaml"],
        compose_project_name=COMPOSE_PROJECT_NAME,
    )

    # Initialize Database
    init_params = [
        "odoo",
        "-c",
        "/etc/odoo/odoo.conf",
        "-i",
        "base",
        "--stop-after-init",
    ]
    if odoo_ver != "6.0":
        init_params += [
            "--max-cron-threads",
            "0",
            "--no-xmlrpc" if odoo_ver in OLDER_VERSIONS else "--no-http",
        ]

    if client_type == "podman":
        subprocess.run(
            [
                "podman",
                "compose",
                "-p",
                COMPOSE_PROJECT_NAME,
                "run",
                "--rm",
                "odoo",
            ]
            + init_params,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
            check=True,
        )
    else:
        docker.compose.run(
            "odoo",
            init_params,
            remove=True,
        )

    # Up Services
    if client_type == "podman":
        subprocess.Popen(
            ["podman", "compose", "-p", COMPOSE_PROJECT_NAME, "up", "--remove-orphans"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    else:
        docker.compose.up(
            detach=True,
            remove_orphans=True,
        )

    print("Waiting Odoo...")
    _wait_for_odoo(env_info["ip"], env_info["ports"]["odoo"])

    try:
        yield docker
    finally:
        docker.compose.down(remove_orphans=True, volumes=True)


@pytest.fixture(scope="session")
def exec_docker(docker_env, env_info):
    def _run(env, args):
        args_str = " ".join(args)
        exec_cmd = f"exec_env {env} {args_str} 2>&1"
        client_type = env_info["client_type"]
        if client_type == "podman":
            return _podman_execute("odoo", ["sh", "-c", exec_cmd], tty=False)
        return docker_env.compose.execute("odoo", ["sh", "-c", exec_cmd], tty=False)

    return _run


@pytest.fixture(scope="session")
def install_module(exec_docker):
    def _run(modname):
        return exec_docker(
            "odoo",
            [
                "odoo",
                "-c",
                "/etc/odoo/odoo.conf",
                "-i",
                modname,
                "--stop-after-init",
            ],
        )

    return _run
