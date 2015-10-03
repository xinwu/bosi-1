import subprocess32 as subprocess
import sys

from threading import Lock

__print_lock = Lock()


def safe_print(message):
    """
    Grab the lock and print to stdout.
    The lock is to serialize messages from
    different thread. 'stty sane' is to
    clean up any hiden space.
    """
    with __print_lock:
        subprocess.call('stty sane', shell=True)
        sys.stdout.write(message)
        sys.stdout.flush()
        subprocess.call('stty sane', shell=True)
