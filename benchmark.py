import subprocess
import matplotlib.pyplot as plt
import re
import textwrap

def run_ab(num_reqs=2000, num_concurrent=2000):
    command = f"ab -n {num_reqs} -c {num_concurrent} http://localhost:8080/"
    result = subprocess.run(command.split(), capture_output=True, text=True)
    
    rps_pattern = r"Requests per second:\s+([\d.]+)"
    rps = re.search(rps_pattern, result.stdout).start()
    
    return rps

def main():
    hor_scale = [10, 20, 30, 40, 50]
    vert_scale = [("100m", "100m", "1"), ("200m", "200m", "4"), ("400m", "400m", "6")]

    rps_list = []
    for v in vert_scale:
      l = []
      for h in hor_scale:
            subprocess.run(["./orchestrator.sh", "scale", "--hor", str(h), "--vert", "--memory", v[0], "--memory-swap", v[1], "--cpuset-cpus", v[2]])
            rps = run_ab()
            l.append(rps)
      rps_list.append(l)

    for i in range(len(vert_scale)):
        plt.clf()
        plt.plot(hor_scale, rps_list[i], marker='o')
        title = 'RPS vs Horizontal Scaling | Memory = ' + vert_scale[i][0] + ', Swap Memory = ' + vert_scale[i][1] + ', CPU Set = ' + vert_scale[i][2]
        wrapped_title = '\n'.join(textwrap.wrap(title, width=60))
        plt.title(wrapped_title)
        plt.xlabel('Number of Containers')
        plt.ylabel('Requests per Second')

        plt.tight_layout()
        plt.savefig(f'plots/plot_vert_{vert_scale[i][0]}_{vert_scale[i][1]}_{vert_scale[i][2]}.png')

if __name__ == "__main__":
    main()
