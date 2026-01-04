
import threading
import requests
import time

def make_request(i):
    try:
        start = time.time()
        r = requests.get("http://localhost:8090/index.html")
        end = time.time()
        print(f"Req {i}: {r.status_code} in {end-start:.3f}s")
    except Exception as e:
        print(f"Req {i}: Error {e}")

threads = []
for i in range(20):
    t = threading.Thread(target=make_request, args=(i,))
    threads.append(t)
    t.start()

for t in threads:
    t.join()

