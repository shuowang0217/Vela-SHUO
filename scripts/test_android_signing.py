"""Offline regression coverage for the Vela permanent Android signing parser."""
import unittest
from finalize_android_signing import EXPECTED_SHA256, extract_certificate_sha256


class AndroidSigningTest(unittest.TestCase):
    def test_normal_android_build_tools(self):
        output = (
            "Verifies\n"
            "Verified using v2 scheme (APK Signature Scheme v2): true\n"
            "Number of signers: 1\n"
            "Signer #1 certificate DN: CN=SHUO Custom\n"
            f"Signer #1 certificate SHA-256 digest: {EXPECTED_SHA256}\n"
        )
        self.assertEqual(extract_certificate_sha256(output), {EXPECTED_SHA256})

    def test_whitespace_and_colon_delimiters(self):
        colon_form = ":".join(EXPECTED_SHA256[i:i + 2] for i in range(0, 64, 2))
        output = f"   Signer #1 certificate SHA-256 digest: {colon_form.upper()} \r\n"
        self.assertEqual(extract_certificate_sha256(output), {EXPECTED_SHA256})

    def test_unrelated_hash_cannot_pass(self):
        output = (
            f"Signer #1 certificate SHA-1 digest: {EXPECTED_SHA256}\n"
            f"APK Signature Scheme SHA-256 digest: {EXPECTED_SHA256}\n"
        )
        self.assertFalse(extract_certificate_sha256(output))


if __name__ == "__main__":
    unittest.main()
