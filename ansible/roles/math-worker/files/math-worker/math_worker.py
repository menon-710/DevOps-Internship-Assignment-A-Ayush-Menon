import os
import asyncio
import signal
import sys
from iii import register_worker, InitOptions, Logger

worker = register_worker(
    os.environ.get("III_URL", "ws://localhost:49134"),
    InitOptions(worker_name="math-worker"),
)
logger = Logger()

def add_handler(payload: dict) -> dict:
    a = payload.get("a", 0)
    b = payload.get("b", 0)
    logger.info(f"math::add called with a={a}, b={b}")
    return {"c": int(a) + int(b)}

worker.register_function("math::add", add_handler)
print("Math worker started - listening for calls")

loop = asyncio.get_event_loop()

def handle_shutdown(sig, frame):
    print(f"Received {sig.name}, shutting down gracefully")
    loop.stop()
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_shutdown)
signal.signal(signal.SIGINT, handle_shutdown)

loop.run_forever()
