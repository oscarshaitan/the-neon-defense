#!/usr/bin/env python3
"""Pre-renders the JS AudioEngine's procedural music and SFX to WAV assets.

The JS game (js/scripts/00_core.js:406-705) synthesizes everything live with
Web Audio oscillators. The loops are fully deterministic per (wave, threat),
so we render them offline once: 15 wave-indexed 16-step "normal" loops, one
"threat" loop, and 4 SFX. Re-run this script if the JS patterns change:

    python3 tool/render_audio.py
"""
import math
import os
import struct
import wave

import numpy as np

SAMPLE_RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")

# JS AudioEngine.notes — incomplete on purpose; missing notes fall back to
# 60 Hz exactly like the JS `this.notes[note] || 60`.
NOTES = {
    "C2": 65.41, "G2": 98.00, "A2": 110.00, "F2": 87.31,
    "C3": 130.81, "Eb3": 155.56, "Gb3": 185.00, "G3": 196.00, "Bb3": 233.08,
    "C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.00,
    "A4": 440.00, "B4": 493.88,
    "C5": 523.25, "D5": 587.33, "Eb5": 622.25, "E5": 659.25, "F5": 698.46,
    "Gb5": 739.99, "G5": 783.99,
}

def note_freq(name):
    return NOTES.get(name, 60.0)

MELODIES_NORMAL = [
    {  # 01: Original High-Tech
        "lead": ["C4", "E4", "G4", 0, "F4", "A4", "C5", 0, "G4", "B4", "D5", 0, "C5", "G4", "E4", "D4"],
        "bass": ["C2", 0, "G2", "C2", "F2", 0, "C3", "F2", "G2", 0, "D3", "G2", "C2", "G2", "E2", "D2"],
    },
    {  # 02: Aeolian Chill
        "lead": ["A4", "C5", "E5", 0, "F4", "A4", "C5", 0, "C4", "E4", "G4", 0, "G4", "B4", "D5", 0],
        "bass": ["A2", 0, "E2", "A2", "F2", 0, "C3", "F2", "C2", 0, "G2", "C2", "G2", 0, "D3", "G2"],
    },
    {  # 03: Dorian Tech
        "lead": ["D4", "F4", "A4", "C5", "G4", "Bb4", "D5", 0, "F4", "A4", "C5", 0, "C4", "E4", "G4", 0],
        "bass": ["D2", 0, "A2", "D2", "G2", 0, "D3", "G2", "F2", 0, "C3", "F2", "C2", 0, "G2", "C2"],
    },
    {  # 04: Phrygian Edge
        "lead": ["E4", "F4", "G4", 0, "F4", "G4", "A4", 0, "G4", "Ab4", "C5", 0, "Eb5", "D5", "C5", "Bb4"],
        "bass": ["E2", 0, "B2", "E2", "F2", 0, "C3", "F2", "G2", 0, "D3", "G2", "Ab2", 0, "Eb3", "Ab2"],
    },
    {  # 05: Pentatonic Pulse
        "lead": ["C4", "D4", "E4", "G4", "A4", "G4", "E4", "D4", "C5", "A4", "G4", "E4", "D4", "C4", "D4", "E4"],
        "bass": ["C2", "C2", "G2", "G2", "A2", "A2", "F2", "F2", "C2", "C2", "G2", "G2", "A2", "A2", "F2", "F2"],
    },
    {  # 06: Lydian Dream
        "lead": ["C4", "E4", "G4", "B4", "D5", "B4", "G4", "E4", "F4", "A4", "C5", "E5", "D5", "C5", "A4", "F4"],
        "bass": ["C2", 0, "G2", "C2", "D2", 0, "A2", "D2", "F2", 0, "C3", "F2", "G2", 0, "D3", "G2"],
    },
    {  # 07: Mixolydian Groove
        "lead": ["G4", "B4", "D5", "F5", "E5", "C5", "B4", "G4", "A4", "C5", "E5", "G4", "F4", "D4", "B3", "G3"],
        "bass": ["G2", 0, "D3", "G2", "F2", 0, "C3", "F2", "C2", 0, "G2", "C2", "Bb2", 0, "F2", "Bb2"],
    },
    {  # 08: Chromatic Tension
        "lead": ["C4", "Db4", "D4", "Eb4", "E4", "Eb4", "D4", "Db4", "C4", "G3", "C4", "Db4", "D4", "A3", "D4", "Eb4"],
        "bass": ["C2", "Db2", "D2", "Eb2", "E2", "Eb2", "D2", "Db2", "C2", "G1", "C2", "Db2", "D2", "A1", "D2", "Eb2"],
    },
    {  # 09: Arp Madness
        "lead": ["C4", "G4", "C5", "G4", "E4", "B4", "E5", "B4", "F4", "C5", "F5", "C5", "G4", "D5", "G5", "D5"],
        "bass": ["C2", 0, 0, 0, "E2", 0, 0, 0, "F2", 0, 0, 0, "G2", 0, 0, 0],
    },
    {  # 10: Syncopated Flow
        "lead": [0, "C4", 0, "E4", "G4", 0, "F4", 0, 0, "A4", 0, "C5", "G4", 0, "D5", 0],
        "bass": ["C2", 0, "G2", 0, "C2", 0, "F2", 0, "F2", 0, "C3", 0, "G2", 0, "D3", 0],
    },
    {  # 11: Minor Gravity
        "lead": ["G4", "Bb4", "D5", "Eb5", "D5", "Bb4", "G4", "F4", "G4", "D4", "G4", "Bb4", "C5", "Bb4", "A4", "F4"],
        "bass": ["G2", 0, "D3", "G2", "Eb2", 0, "Bb2", "Eb2", "C2", 0, "G2", "C2", "F2", 0, "C3", "F2"],
    },
    {  # 12: Cyber Funk
        "lead": ["C4", 0, "C4", "Eb4", 0, "F4", "Gb4", "G4", 0, "Bb4", 0, "C5", 0, "G4", "Eb4", "C4"],
        "bass": ["C2", "C2", 0, "Eb2", "Eb2", 0, "F2", "G2", "C2", "C2", 0, "Bb1", "Bb1", 0, "G1", "F1"],
    },
    {  # 13: Neon Echo
        "lead": ["C5", 0, "G4", 0, "E4", 0, "C4", 0, "D5", 0, "A4", 0, "F4", 0, "D4", 0],
        "bass": ["C2", "G2", "C3", "G2", "A2", "E3", "A3", "E3", "F2", "C3", "F3", "C3", "G2", "D3", "G3", "D3"],
    },
    {  # 14: Dark Wave
        "lead": ["A3", "C4", "E4", "A4", "G4", "E4", "C4", "B3", "F3", "A3", "C4", "F4", "E4", "C4", "A3", "G3"],
        "bass": ["A1", "A1", "E2", "E2", "G1", "G1", "D2", "D2", "F1", "F1", "C2", "C2", "E1", "E1", "B1", "B1"],
    },
    {  # 15: Final Stand
        "lead": ["E4", "E4", "G4", "A4", "B4", "B4", "D5", "E5", "D5", "D5", "B4", "A4", "G4", "G4", "E4", "D4"],
        "bass": ["E2", "E2", "G2", "G2", "A2", "A2", "B2", "B2", "D3", "D3", "B2", "B2", "A2", "A2", "G2", "F2"],
    },
]

MELODY_THREAT = {
    "lead": ["C5", "Eb5", "G5", "Eb5", "Gb5", "Eb5", "C5", "Bb4", "C5", "Eb5", "Gb5", "Eb5", "F5", "Eb5", "D5", "Bb4"],
    "bass": ["C2", 0, "C2", 0, "Eb2", 0, "Eb2", 0, "Gb2", 0, "Gb2", 0, "G2", 0, "G2", 0],
}


def osc(kind, freq, t):
    """Web Audio oscillator waveforms. freq may be an array (ramps)."""
    phase = 2 * np.pi * np.cumsum(np.atleast_1d(freq) / SAMPLE_RATE) \
        if np.ndim(freq) else 2 * np.pi * freq * t
    if kind == "sine":
        return np.sin(phase)
    if kind == "square":
        return np.sign(np.sin(phase))
    if kind == "sawtooth":
        return 2 * (phase / (2 * np.pi) % 1) - 1
    if kind == "triangle":
        return 2 * np.abs(2 * (phase / (2 * np.pi) % 1) - 1) - 1
    raise ValueError(kind)


def exp_ramp(start, end, n):
    """Web Audio exponentialRampToValueAtTime curve."""
    return start * (end / start) ** (np.arange(n) / max(1, n - 1))


def render_note(kind, freq, vol, duration):
    """JS playNote: constant freq, gain exp ramp vol -> 0.001."""
    n = int(duration * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE
    return osc(kind, freq, t) * exp_ramp(vol, 0.001, n)


def render_arp(kind, base_freq, vol, duration):
    """JS playArp: root, x1.25, x1.5, x2 at 0.05 s steps."""
    n = int(duration * SAMPLE_RATE)
    freqs = np.full(n, base_freq)
    arp = int(0.05 * SAMPLE_RATE)
    for i, mult in enumerate([1.0, 1.25, 1.5, 2.0]):
        freqs[min(n, i * arp):] = base_freq * mult
    return osc(kind, freqs, None) * exp_ramp(vol, 0.001, n)


def render_loop(melody, threat=False):
    step_time = 0.125 if threat else 0.2
    total = int(16 * step_time * SAMPLE_RATE)
    buf = np.zeros(total)
    for step in range(16):
        at = int(step * step_time * SAMPLE_RATE)
        bass = melody["bass"][step]
        if bass:
            sig = render_note("triangle", note_freq(bass), 0.1, step_time * 0.9)
            buf[at:at + len(sig)] += sig[: total - at]
        lead = melody["lead"][step]
        if lead:
            if threat and step % 4 == 0:
                sig = render_arp("square", note_freq(lead), 0.05, step_time * 0.8)
            else:
                sig = render_note("square", note_freq(lead), 0.05, step_time * 0.7)
            buf[at:at + len(sig)] += sig[: total - at]
    return buf


def render_sfx(name):
    if name == "shoot":  # square 400 -> 100 exp, 0.1 s, vol .05 exp decay
        n = int(0.1 * SAMPLE_RATE)
        return osc("square", exp_ramp(400, 100, n), None) * exp_ramp(0.05, 0.001, n)
    if name == "explosion":  # saw 100 -> 10 exp, 0.3 s, vol .1 linear decay
        n = int(0.3 * SAMPLE_RATE)
        return osc("sawtooth", exp_ramp(100, 10, n), None) * np.linspace(0.1, 0, n)
    if name == "hit":  # triangle 150 -> 50 linear, 0.2 s, vol .2 linear decay
        n = int(0.2 * SAMPLE_RATE)
        return osc("triangle", np.linspace(150, 50, n), None) * np.linspace(0.2, 0, n)
    if name == "build":  # sine 200 -> 800 exp, 0.2 s, vol .05 exp decay
        n = int(0.2 * SAMPLE_RATE)
        return osc("sine", exp_ramp(200, 800, n), None) * exp_ramp(0.05, 0.001, n)
    raise ValueError(name)


def write_wav(path, signal, gain=4.0):
    # JS music/sfx gains are low (0.05-0.2); boost into a sane WAV range.
    data = np.clip(signal * gain, -1, 1)
    pcm = (data * 32767).astype("<i2")
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        f.writeframes(pcm.tobytes())
    print(f"  {os.path.basename(path)}  {os.path.getsize(path) // 1024} KB")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Rendering music loops:")
    for i, melody in enumerate(MELODIES_NORMAL, start=1):
        write_wav(os.path.join(OUT_DIR, f"music_normal_{i:02d}.wav"),
                  render_loop(melody))
    write_wav(os.path.join(OUT_DIR, "music_threat.wav"),
              render_loop(MELODY_THREAT, threat=True))
    print("Rendering SFX:")
    for name in ["shoot", "explosion", "hit", "build"]:
        write_wav(os.path.join(OUT_DIR, f"{name}.wav"), render_sfx(name))


if __name__ == "__main__":
    main()
