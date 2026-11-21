import base64
import json
import os
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

_TEST_DATA = tempfile.TemporaryDirectory(prefix="scamshield-video-test-")
os.environ.setdefault("DATA_DIR", _TEST_DATA.name)
os.environ.setdefault("DB_PATH", str(Path(_TEST_DATA.name) / "video-test.db"))
os.environ.setdefault("SECRET_KEY", "video-analysis-test-secret")
os.environ.setdefault("ADMIN_KEY", "")
os.environ.setdefault("NEWS_ENABLED", "false")
os.environ.setdefault("ALLOW_REGISTRATION", "true")
os.environ["AI_PROVIDER"] = "gemini"

import server


class VideoAnalysisApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        server.app.config.update(TESTING=True)
        cls.client = server.app.test_client()

    def setUp(self):
        server._hits.clear()

    def register(self):
        email = f"video-{uuid.uuid4().hex[:8]}@example.test"
        response = self.client.post(
            "/api/register",
            json={"email": email, "password": "test-password-123", "username": "VideoTest"},
        )
        self.assertEqual(response.status_code, 200, response.get_json())
        return {"Authorization": "Bearer " + response.get_json()["token"]}

    def payload(self, count=4, confidence="HIGH", probability=0.82):
        # The endpoint validates the JPEG signature and size; AI itself is mocked below.
        jpeg = b"\\xff\\xd8\\xff\\xe0" + b"test-frame-data"
        frames = []
        for index in range(count):
            frames.append({
                "timestamp_ms": 500 + index * 900,
                "mime": "image/jpeg",
                "data": base64.b64encode(jpeg).decode("ascii"),
            })
        return {
            "duration_ms": 5000,
            "frames": frames,
        }

    def test_requires_authentication(self):
        response = self.client.post("/api/analyze/video", json=self.payload())
        self.assertIn(response.status_code, (401, 403))

    def test_rejects_too_few_frames(self):
        headers = self.register()
        response = self.client.post(
            "/api/analyze/video",
            json=self.payload(count=2),
            headers=headers,
        )
        self.assertEqual(response.status_code, 400)

    def test_sends_all_sampled_frames_to_vision_and_returns_cautious_verdict(self):
        headers = self.register()
        raw = json.dumps({
            "fake_probability": 0.82,
            "confidence": "HIGH",
            "note": "Có dấu hiệu không nhất quán quanh vùng mặt giữa các khung.",
        }, ensure_ascii=False)
        with patch.object(server, "ai_generate", return_value=raw) as ai_call:
            response = self.client.post(
                "/api/analyze/video",
                json=self.payload(count=4),
                headers=headers,
            )
        self.assertEqual(response.status_code, 200, response.get_json())
        result = response.get_json()
        self.assertEqual(result["verdict"], "likely_fake")
        self.assertEqual(result["frames_analyzed"], 4)
        sent_content = ai_call.call_args.args[1]
        self.assertEqual(sum(1 for item in sent_content if item.get("type") == "image"), 4)
        self.assertEqual(sent_content[-1]["type"], "text")

    def test_low_confidence_never_returns_no_obvious_signs(self):
        headers = self.register()
        raw = json.dumps({
            "fake_probability": 0.02,
            "confidence": "LOW",
            "note": "Không nhìn rõ khuôn mặt.",
        }, ensure_ascii=False)
        with patch.object(server, "ai_generate", return_value=raw):
            response = self.client.post(
                "/api/analyze/video",
                json=self.payload(count=3),
                headers=headers,
            )
        self.assertEqual(response.status_code, 200, response.get_json())
        self.assertEqual(response.get_json()["verdict"], "unverified")


if __name__ == "__main__":
    unittest.main()
