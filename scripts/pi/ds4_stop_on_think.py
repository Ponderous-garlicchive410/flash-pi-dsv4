#!/usr/bin/env python3
import errno
import os
import select
import signal
import subprocess
import sys
import termios
import tty


PATTERN = os.environ.get("DS4_STOP_PATTERN", "</think>").encode()
MARKERS = (b"ds4:", b"ds4> ")
MARKER_KEEP = max(len(m) for m in MARKERS) - 1


def write_stdout(data):
    if data:
        os.write(sys.stdout.fileno(), data)


def partial_pattern_suffix_len(data):
    max_keep = min(len(data), len(PATTERN) - 1)
    for n in range(max_keep, 0, -1):
        if PATTERN.startswith(data[-n:]):
            return n
    return 0


def main():
    if len(sys.argv) < 2:
        print("usage: ds4_stop_on_think.py COMMAND [ARGS...]", file=sys.stderr)
        return 2

    master_fd, slave_fd = os.openpty()
    proc = subprocess.Popen(
        sys.argv[1:],
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        preexec_fn=os.setsid,
        close_fds=True,
    )
    os.close(slave_fd)

    def forward_signal(signum, _frame):
        try:
            os.killpg(proc.pid, signum)
        except ProcessLookupError:
            pass

    signal.signal(signal.SIGINT, forward_signal)
    signal.signal(signal.SIGTERM, forward_signal)

    stdin_fd = sys.stdin.fileno()
    stdin_is_tty = os.isatty(stdin_fd)
    old_term = None
    if stdin_is_tty:
        old_term = termios.tcgetattr(stdin_fd)
        tty.setraw(stdin_fd)

    pending = b""
    suppress = False
    suppress_buf = b""
    stdin_open = not sys.stdin.closed

    try:
        while True:
            readable = [master_fd]
            if stdin_open:
                readable.append(stdin_fd)
            ready, _, _ = select.select(readable, [], [], 0.1)
            if not ready:
                if proc.poll() is not None:
                    break
                continue

            if stdin_open and stdin_fd in ready:
                try:
                    data = os.read(stdin_fd, 4096)
                except OSError:
                    data = b""
                if data:
                    if b"\x03" in data:
                        try:
                            os.killpg(proc.pid, signal.SIGINT)
                        except ProcessLookupError:
                            pass
                        data = data.replace(b"\x03", b"")
                    if data:
                        os.write(master_fd, data)
                else:
                    stdin_open = False

            if master_fd not in ready:
                continue

            try:
                data = os.read(master_fd, 4096)
            except OSError as exc:
                if exc.errno == errno.EIO:
                    break
                raise
            if not data:
                break

            if suppress:
                suppress_buf += data
                hits = [suppress_buf.find(marker) for marker in MARKERS]
                hits = [hit for hit in hits if hit >= 0]
                if hits:
                    idx = min(hits)
                    write_stdout(suppress_buf[idx:])
                    suppress = False
                    suppress_buf = b""
                else:
                    suppress_buf = suppress_buf[-MARKER_KEEP:] if MARKER_KEEP > 0 else b""
                continue

            pending += data
            idx = pending.find(PATTERN)
            if idx >= 0:
                write_stdout(pending[:idx])
                pending = b""
                try:
                    os.killpg(proc.pid, signal.SIGINT)
                except ProcessLookupError:
                    pass
                suppress = True
                suppress_buf = b""
                continue

            keep = partial_pattern_suffix_len(pending)
            if len(pending) > keep:
                if keep:
                    write_stdout(pending[:-keep])
                    pending = pending[-keep:]
                else:
                    write_stdout(pending)
                    pending = b""

        if pending and not suppress:
            write_stdout(pending)
        return proc.wait()
    finally:
        if old_term is not None:
            termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_term)
        try:
            os.close(master_fd)
        except OSError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
