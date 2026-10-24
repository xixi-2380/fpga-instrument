"""Verify protocol v1 golden bytes. Standard library only; not a hardware test."""

from pathlib import Path
import binascii
import json
import struct
import zlib


def crc16(data):
    value = 0xFFFF
    for byte in data:
        value ^= byte << 8
        for _ in range(8):
            value = ((value << 1) ^ (0x1021 if value & 0x8000 else 0)) & 0xFFFF
    return value


def crc32(data):
    value = 0xFFFFFFFF
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = (value >> 1) ^ (0xEDB88320 if value & 1 else 0)
    return value ^ 0xFFFFFFFF


def check(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    root = Path(__file__).resolve().parent
    vectors = json.loads((root / "protocol_vectors.json").read_text(encoding="utf-8"))
    check(crc16(b"123456789") == 0x29B1, "CRC16 standard check")
    check(crc32(b"123456789") == 0xCBF43926, "CRC32 standard check")
    score = b"".join(
        struct.pack("<IBBH", item["start_ms"], item["note"], item["velocity"], item["duration_ms"])
        for item in vectors["notes"]
    )
    check(score == bytes.fromhex(vectors["score_hex"]), "Score record layout")
    check(crc32(score) == zlib.crc32(score) == int(vectors["score_crc32"], 16), "Score CRC32")
    duration = max(item["start_ms"] + item["duration_ms"] for item in vectors["notes"])
    check(duration == vectors["song_duration_ms"], "Song duration")
    frames = {}
    for name, item in vectors["frames"].items():
        frame = bytes.fromhex(item["frame_hex"])
        check(len(frame) >= 10 and frame[:2] == b"\xA5\x5A", f"{name}: frame header")
        version, command, seq, length = struct.unpack_from("<BBHH", frame, 2)
        payload = frame[8:-2]
        check(version == 1 and command == item["cmd"] and seq == item["seq"], f"{name}: fields")
        check(length == len(payload) <= 256 and len(frame) == 10 + length, f"{name}: length")
        check(payload == bytes.fromhex(item["payload_hex"]), f"{name}: payload")
        expected_crc = struct.unpack_from("<H", frame, len(frame) - 2)[0]
        check(crc16(frame[2:-2]) == binascii.crc_hqx(frame[2:-2], 0xFFFF) == expected_crc, f"{name}: CRC16")
        frames[name] = (command, seq, payload)
    check(frames["hello"][1:] == (0, b""), "HELLO request")
    count, expected_score_crc = struct.unpack("<HI", frames["begin"][2])
    check(count == len(vectors["notes"]) and expected_score_crc == crc32(score), "BEGIN content")
    check(frames["data"][2] == b"\x00\x00" + score, "DATA content")
    check(frames["data_ack"][2] == struct.pack("<BH", 0, count), "DATA next_index")
    check(frames["commit_ack"][2] == struct.pack("<BI", 0, duration), "COMMIT duration")
    for name in ("hello", "begin", "data", "commit", "play"):
        request, reply = frames[name], frames[name + "_ack"]
        check(reply[0] == request[0] | 0x80 and reply[1] == request[1] and reply[2][0] == 0, f"{name}: response match")
    cap = frames["hello_ack"][2]
    check(len(cap) == 20 and cap[1:3] == b"\x01\x01", "HELLO capability size/version")
    max_payload, max_notes = struct.unpack_from("<HH", cap, 3)
    check(max_payload == 256 and max_notes >= count, "HELLO capacity")
    check(cap[8] <= min(item["note"] for item in vectors["notes"]) <= max(item["note"] for item in vectors["notes"]) <= cap[9], "HELLO note range")
    overhead = (10 + 20) + 10 + (10 + 6) + (10 + 3) + 10 + (10 + 5)
    full_upload_bytes = 64 * ((10 + 2 + 16 * 8) + (10 + 3)) + overhead
    check(full_upload_bytes == 9886, "Full upload byte budget")
    docs = "\n".join(path.read_text(encoding="utf-8") for path in root.glob("*.md"))
    for name, item in vectors["frames"].items():
        if name not in ("hello_ack", "play_ack"):
            check(item["frame_hex"] in docs, f"{name}: Markdown example differs")
    print(f"PASS: {len(frames)} golden frames; CRC16/CRC32; score layout; response fields; Markdown examples.")
    print(f"PASS: 1024-note upload budget {full_upload_bytes} bytes, {full_upload_bytes * 10 / 9600:.2f}s at 9600, {full_upload_bytes * 10 / 115200:.2f}s at 115200 (UART time only).")
    print("Not tested: RTL, Android app, radio link, actual UART, audio playback.")


if __name__ == "__main__":
    main()
