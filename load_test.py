import asyncio
from time import perf_counter
import aiohttp
import argparse
import sys

N = 3000
URL = "http://172.17.4.2:8080/get_and_increment_counter"


async def fetch(s):
    try:
      resp = await s.get(URL, allow_redirects=True)
      if resp.status in [500,404]:
          raise Exception(resp.status)
      elif resp.status == 307:
          print("OK")
    except Exception as e:
        print(e)
        sys.exit(1)

async def fetch_all(s):
    tasks = []
    for _ in range(N):
        task = asyncio.create_task(fetch(s))
        tasks.append(task)
    await asyncio.gather(*tasks)


async def main():
    async with aiohttp.ClientSession() as session:
        await fetch_all(session)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Concurrent HTTP requests benchmarking tool"
    )
    parser.add_argument("url", type=str, help="URL to test")
    parser.add_argument(
        "--num-requests",
        type=int,
        default=100,
        help="Number of requests to make (default: 100)",
    )
    args = parser.parse_args()

    N = args.num_requests
    URL = args.url

    start = perf_counter()
    asyncio.run(main())
    stop = perf_counter()

    print("Requests per second (RPS):", N / (stop - start))
