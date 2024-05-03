import subprocess
import argparse
from joblib import Parallel, delayed, parallel_backend


def parse_memory_format(memory_string):
    unit_multiplier = {
        "m": 1024**2,
        "g": 1024**3,
        "k": 1024,
    }

    try:
        value = memory_string.lower()[:-1]
        unit = memory_string.lower()[-1]
        return int(value) * unit_multiplier.get(unit, 1)
    except ValueError:
        raise ValueError(f"Invalid memory format: {memory_string}")


def existing():
    docker_ps_command = ["docker", "ps", "--format", "{{.Names}}"]
    docker_ps_process = subprocess.Popen(docker_ps_command, stdout=subprocess.PIPE)

    grep_command = ["grep", "-E", "^f[0-9]+$"]
    grep_process = subprocess.Popen(
        grep_command, stdin=docker_ps_process.stdout, stdout=subprocess.PIPE
    )

    output, _ = grep_process.communicate()
    names = sorted([int(x[1:]) for x in output.decode("utf-8").strip().split("\n")])
    return names


def hor_scale(N):
    existing_names = set(existing())
    delta = N - len(existing_names)

    if delta > 0:
        all_nums = set(range(1, 1 + max(existing_names) + delta))
        new_nums = sorted(list(all_nums - existing_names))

        def add_container(n):
            subprocess.run(["./orchestrator.sh", "add", str(n)])

        with parallel_backend("loky", n_jobs=len(new_nums)):
            Parallel(n_jobs=len(new_nums))(delayed(add_container)(n) for n in new_nums)

    elif delta < 0:

        def remove_container(n):
            subprocess.run(["./orchestrator.sh", "rm", f"f{n}"])

        with parallel_backend("loky", n_jobs=-delta):
            Parallel(n_jobs=-delta)(
                delayed(remove_container)(n)
                for n in sorted(list(existing_names), reverse=True)[:-delta]
            )

    subprocess.run(["./load_balancer.sh", "reload"])


def vert_scale(memory, swap_memory=None, cpuset_cpus=None):
    if parse_memory_format(memory) > parse_memory_format(swap_memory):
        swap_memory = memory

    names = [f"f{x}" for x in existing()] + ["leader", "load_balancer"]
    subprocess.run(
        [
            "docker",
            "update",
            f"--memory={memory}",
            f"--memory-swap={swap_memory}",
            f"--cpuset-cpus={cpuset_cpus}",
            *names,
        ]
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Scale the number of containers or the resource limits of the containers."
    )
    parser.add_argument(
        "--hor", type=int, help="Number of containers to horizontally scale to."
    )
    parser.add_argument(
        "--vert", action="store_true", help="Resource limits to vertically scale to."
    )
    parser.add_argument(
        "--memory", type=str, help="Memory limit for the containers.", default="100m"
    )
    parser.add_argument(
        "--memory-swap",
        type=str,
        help="Swap memory limit for the containers.",
        default="100m",
    )
    parser.add_argument(
        "--cpuset-cpus", type=str, help="CPU set for the containers.", default="1"
    )
    args = parser.parse_args()

    if args.hor:
        hor_scale(args.hor)
    if args.vert:
        vert_scale(args.memory, args.memory_swap, args.cpuset_cpus)
