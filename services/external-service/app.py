from quart import Quart
from aiohttp import ClientSession
import os


COUNTER_SERVICE_URL = 'http://192.168.2.2:8080' if "URL" not in os.environ.keys() else os.environ["URL"]

app = Quart(__name__)

async def fetch_counter():
    async with ClientSession() as session:
      async with session.get(COUNTER_SERVICE_URL + '/get_and_increment_counter') as response:
          return await response.text()

@app.route('/')
async def hello_world():
    counter = await fetch_counter()
    return 'Hello CS695 Explorers! You have sent request to this container ' + counter + ' times.'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)