import contextlib
import io
import unittest
from unittest.mock import Mock, patch

import record


class CountdownTests(unittest.TestCase):
    def test_notification_persists_and_reuses_id(self):
        with patch.object(record, "notification_call", return_value="(uint32 42,)") as call:
            self.assertEqual(record.show_countdown(3, 42), 42)
        self.assertEqual(call.call_args.args[2], "42")
        self.assertEqual(call.call_args.args[-1], "0")

    def run_command(self, arguments, active=False, sleep_error=None):
        ws = Mock()
        events = []

        def request(_, name):
            events.append(name)
            return {"outputActive": active} if name == "GetRecordStatus" else {}

        def sleep(seconds):
            events.append(("sleep", seconds))
            if sleep_error:
                raise sleep_error

        with patch.object(record, "connect_for_recording", return_value=ws), \
             patch.object(record, "show_countdown", return_value=42) as show, \
             patch.object(record, "close_countdown") as close, \
             patch.object(record, "request", side_effect=request), \
             patch.object(record.time, "sleep", side_effect=sleep), \
             patch.object(record.sys, "argv", ["record", *arguments]), \
             contextlib.redirect_stdout(io.StringIO()):
            if sleep_error:
                with self.assertRaises(KeyboardInterrupt):
                    record.main()
            else:
                record.main()
        ws.close.assert_called_once()
        if not active:
            close.assert_called_once_with(42)
            self.assertEqual(show.call_args_list[0].args[1], 0)
        return events

    def test_start_only_after_countdown(self):
        self.assertEqual(self.run_command(["--delay", "2"]),
                         ["GetRecordStatus", ("sleep", 1), ("sleep", 1), "StartRecord"])

    def test_cancel_does_not_start(self):
        self.assertEqual(self.run_command(["--delay", "2"], sleep_error=KeyboardInterrupt()),
                         ["GetRecordStatus", ("sleep", 1)])

    def test_existing_recording_is_untouched(self):
        self.assertEqual(self.run_command(["--delay", "2"], active=True), ["GetRecordStatus"])

    def test_default_is_five_seconds(self):
        self.assertEqual(self.run_command([]),
                         ["GetRecordStatus"] + [("sleep", 1)] * 5 + ["StartRecord"])


class StopTests(unittest.TestCase):
    def test_unavailable_optional_outputs_allow_close(self):
        with patch.object(record, "request", side_effect=[
            {"outputActive": False}, record.OBSOutputUnavailable(), record.OBSOutputUnavailable()
        ]), patch.object(record, "close_obs") as close, \
             contextlib.redirect_stdout(io.StringIO()):
            record.stop_recording(Mock(), False)
        close.assert_called_once()

    def test_save_before_close(self):
        events = []
        def request(_, name):
            events.append(name)
            return {"outputPath": "/tmp/test.mkv"} if name == "StopRecord" else {"outputActive": False}
        with patch.object(record, "request", side_effect=request), \
             patch.object(record, "close_obs", side_effect=lambda: events.append("close")), \
             contextlib.redirect_stdout(io.StringIO()):
            record.stop_recording(Mock(), True)
        self.assertEqual(events[0], "StopRecord")
        self.assertEqual(events[-1], "close")

    def test_failed_save_keeps_obs_open(self):
        with patch.object(record, "request", side_effect=RuntimeError("Save failed")), \
             patch.object(record, "close_obs") as close:
            with self.assertRaises(RuntimeError):
                record.stop_recording(Mock(), True)
        close.assert_not_called()

    def test_other_output_keeps_obs_open(self):
        with patch.object(record, "request", return_value={"outputActive": True}), \
             patch.object(record, "close_obs") as close, \
             contextlib.redirect_stdout(io.StringIO()):
            record.stop_recording(Mock(), False)
        close.assert_not_called()


class StartupTests(unittest.TestCase):
    def test_closed_obs_launches_once_and_waits(self):
        ws = Mock()
        process = Mock()
        process.poll.return_value = None
        with patch.object(record, "connect", side_effect=[ConnectionRefusedError(), ConnectionRefusedError(), ws]), \
             patch.object(record, "obs_running", return_value=False), \
             patch.object(record, "launch_obs", return_value=process) as launch, \
             patch.object(record, "request", return_value={}), \
             patch.object(record.time, "sleep"):
            self.assertIs(record.connect_for_recording(), ws)
        launch.assert_called_once()

    def test_existing_obs_is_not_relaunched(self):
        ws = Mock()
        with patch.object(record, "connect", side_effect=[ConnectionRefusedError(), ws]), \
             patch.object(record, "obs_running", return_value=True), \
             patch.object(record, "launch_obs") as launch, \
             patch.object(record, "request", return_value={}), \
             patch.object(record.time, "sleep"):
            self.assertIs(record.connect_for_recording(), ws)
        launch.assert_not_called()

    def test_startup_timeout(self):
        with patch.object(record, "connect", side_effect=ConnectionRefusedError()), \
             patch.object(record, "obs_running", return_value=True), \
             patch.object(record.time, "monotonic", side_effect=[0, 61]):
            with self.assertRaisesRegex(RuntimeError, "60 seconds"):
                record.connect_for_recording()


if __name__ == "__main__":
    unittest.main()
