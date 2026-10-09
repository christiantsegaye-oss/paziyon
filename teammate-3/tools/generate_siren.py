"""Generates the alert siren: an ambulance-style wail that loops without gaps.

A tone sweeps 650 → 1450 → 650 Hz every 3 seconds. Odd harmonics make it
harsher and easier to hear over street noise than a pure sine. Written as WAV
(not MP3) because MP3 encoders pad the ends, which leaves a click when looping.

    python3 tools/generate_siren.py
"""
import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RATE = 22050
CYCLE = 3.0          # seconds per up-and-down sweep; the file is exactly one cycle
LOW, HIGH = 650.0, 1450.0


def main() -> None:
    n = int(RATE * CYCLE)
    samples = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        # Smooth up-and-down sweep (cosine), so the loop point matches exactly.
        f = LOW + (HIGH - LOW) * (1 - math.cos(2 * math.pi * t / CYCLE)) / 2
        phase += 2 * math.pi * f / RATE
        s = math.sin(phase) + 0.35 * math.sin(3 * phase) + 0.18 * math.sin(5 * phase)
        samples.append(math.tanh(1.6 * s))  # soft clip: louder without harsh distortion
    peak = max(abs(s) for s in samples)
    frames = b''.join(struct.pack('<h', int(s / peak * 0.97 * 32767)) for s in samples)
    for out in [ROOT / 'app/assets/audio/siren.wav', ROOT / 'prototype/audio/siren.wav']:
        with wave.open(str(out), 'wb') as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(frames)
        print(f'wrote {out} ({len(frames) // 1024} KB)')


if __name__ == '__main__':
    main()
