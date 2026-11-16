"""
Unit tests for AlertManager in edge_metrics_agent.py.
Tests failure threshold hysteresis, recovery alerts, and cooldown logic.
"""

import sys
import unittest
from unittest.mock import MagicMock

# Mock external modules if running in an environment without them (e.g. local Mac)
for mod in ["psutil", "redis", "jose"]:
    if mod not in sys.modules:
        sys.modules[mod] = MagicMock()

from edge_metrics_agent import AlertManager


class TestAlertManager(unittest.TestCase):
    def setUp(self):
        self.sent_messages = []

        def fake_send(text: str):
            self.sent_messages.append(text)

        self.alerter = AlertManager(
            node_id="node-test",
            token="test-token",
            chat_id="test-chat-id",
            fail_threshold=3,
        )
        # Mock the internal _send to capture output
        self.alerter._send = fake_send

    def test_baseline_initialization_sends_no_alert(self):
        # First cycle establishes baseline
        results = {"ai_proxy": {"healthy": True}}
        self.alerter.check_services(results)
        self.assertEqual(len(self.sent_messages), 0)
        self.assertTrue(self.alerter._initialized)
        self.assertEqual(self.alerter._prev_health["ai_proxy"], True)
        self.assertEqual(self.alerter._fail_counts["ai_proxy"], 0)

    def test_transient_failures_below_threshold_do_not_alert(self):
        # Baseline
        self.alerter.check_services({"ai_proxy": {"healthy": True}})

        # 1st failure (e.g. service restarting, takes 2 seconds)
        self.alerter.check_services({"ai_proxy": {"healthy": False, "error": "Connection refused"}})
        self.assertEqual(len(self.sent_messages), 0, "1st failure should not trigger alert")
        self.assertEqual(self.alerter._fail_counts["ai_proxy"], 1)

        # 2nd failure
        self.alerter.check_services({"ai_proxy": {"healthy": False, "error": "Connection refused"}})
        self.assertEqual(len(self.sent_messages), 0, "2nd failure should not trigger alert")
        self.assertEqual(self.alerter._fail_counts["ai_proxy"], 2)

        # Service recovers before threshold
        self.alerter.check_services({"ai_proxy": {"healthy": True}})
        self.assertEqual(len(self.sent_messages), 0, "Quick recovery should not trigger alert")
        self.assertEqual(self.alerter._fail_counts["ai_proxy"], 0)
        self.assertFalse(self.alerter._alerted_down.get("ai_proxy", False))

    def test_persistent_failure_triggers_down_and_recovery_alerts(self):
        # Baseline
        self.alerter.check_services({"ai_proxy": {"healthy": True}})

        # 3 consecutive failures
        self.alerter.check_services({"ai_proxy": {"healthy": False, "error": "Connection refused"}})
        self.alerter.check_services({"ai_proxy": {"healthy": False, "error": "Connection refused"}})
        self.alerter.check_services({"ai_proxy": {"healthy": False, "error": "Connection refused"}})

        # Now threshold is reached
        self.assertEqual(len(self.sent_messages), 1, "3rd consecutive failure must trigger DOWN alert")
        self.assertIn("DOWN", self.sent_messages[0])
        self.assertIn("node-test", self.sent_messages[0])
        self.assertIn("ai_proxy", self.sent_messages[0])
        self.assertTrue(self.alerter._alerted_down["ai_proxy"])

        # 4th failure (during cooldown) should not spam
        self.alerter.check_services({"ai_proxy": {"healthy": False, "error": "Connection refused"}})
        self.assertEqual(len(self.sent_messages), 1, "Repeated failure during cooldown should not spam")

        # Recovery after confirmed DOWN
        self.alerter.check_services({"ai_proxy": {"healthy": True}})
        self.assertEqual(len(self.sent_messages), 2, "Recovery after DOWN must trigger kurtarıldı alert")
        self.assertIn("kurtarıldı", self.sent_messages[1])
        self.assertFalse(self.alerter._alerted_down["ai_proxy"])
        self.assertEqual(self.alerter._fail_counts["ai_proxy"], 0)

    def test_resource_thresholds(self):
        # Normal resources
        self.alerter.check_resources(cpu=30.0, ram_pct=50.0, disk_pct=60.0)
        self.assertEqual(len(self.sent_messages), 0)

        # Exceeding CPU threshold
        self.alerter.check_resources(cpu=95.0, ram_pct=50.0, disk_pct=60.0)
        self.assertEqual(len(self.sent_messages), 1)
        self.assertIn("CPU %95", self.sent_messages[0])


if __name__ == "__main__":
    unittest.main()
