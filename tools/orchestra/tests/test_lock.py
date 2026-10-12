"""Real OS data-directory locking, without invoking Codex or persistent services."""
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
from server import DataDirectoryLock


class LockTests(unittest.TestCase):
    def test_second_owner_rejected_then_reacquire_after_close(self):
        with tempfile.TemporaryDirectory() as directory:
            first = DataDirectoryLock(directory)
            try:
                with self.assertRaises(RuntimeError):
                    DataDirectoryLock(directory)
            finally:
                first.close()
                first.close()
            second = DataDirectoryLock(directory)
            second.close()
    def test_different_port_server_cannot_recover_owned_database(self):
        with tempfile.TemporaryDirectory() as directory:
            first = DataDirectoryLock(directory)
            try:
                with socket.socket() as listener:
                    listener.bind(("127.0.0.1", 0))
                    port = listener.getsockname()[1]
                result = subprocess.run([sys.executable, str(TOOLS / "server.py"), "--port", str(port), "--project", directory, "--data-dir", directory], capture_output=True, text=True, timeout=8)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Another Orchestra server owns this data directory", result.stderr)
                self.assertFalse((Path(directory) / "orchestra.sqlite3").exists())
                self.assertFalse((Path(directory) / "connection.json").exists())
            finally:
                first.close()


if __name__ == "__main__":
    unittest.main()
