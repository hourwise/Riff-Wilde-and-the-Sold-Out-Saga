#!/usr/bin/env python3
"""Trim a sound to length with a fade, for game-ready one-shots.

    python tools/trim_sound.py <in.wav> <out.wav> --length 0.5 [--fade 0.12]
                               [--peak -1.0] [--report]

Library sounds are recorded to their natural end. A guitar chord recorded until
it stops ringing is three seconds long, and most of that is a tail at -35 dB that
you would never notice on its own — but a weapon swung several times a second
stacks those tails into a drone, and each one holds a voice in the pool while it
plays out.

So one-shots get cut to the part that carries the hit. The fade is not optional:
cutting a decaying waveform at an arbitrary sample leaves a step to silence, which
is a click, and a click is far more audible than the tail you removed.

--report prints the decay envelope instead of writing anything, so the trim point
can be chosen from the sound rather than guessed at.
"""

import argparse
import math
import struct
import sys
import wave

FORMATS = {1: "b", 2: "h", 4: "i"}


def read_wav(path):
    with wave.open(path, "rb") as handle:
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        rate = handle.getframerate()
        frames = handle.getnframes()
        raw = handle.readframes(frames)

    if width not in FORMATS:
        raise SystemExit("unsupported sample width: %d bytes" % width)

    samples = list(struct.unpack("<%d%s" % (frames * channels, FORMATS[width]), raw))
    return samples, channels, width, rate, frames


def write_wav(path, samples, channels, width, rate):
    raw = struct.pack("<%d%s" % (len(samples), FORMATS[width]), *samples)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(channels)
        handle.setsampwidth(width)
        handle.setframerate(rate)
        handle.writeframes(raw)


def envelope(samples, channels, width, rate, window=0.01):
    """Peak level per window, in dB below the loudest window."""
    full_scale = float(1 << (width * 8 - 1))
    step = max(1, int(rate * window))
    frames = len(samples) // channels

    levels = []
    for start in range(0, frames, step):
        loudest = 0.0
        for frame in range(start, min(start + step, frames)):
            for channel in range(channels):
                loudest = max(loudest, abs(samples[frame * channels + channel]) / full_scale)
        levels.append(loudest)

    peak = max(levels) if levels else 0.0
    return [(-99.0 if v <= 0 or peak <= 0 else 20 * math.log10(v / peak)) for v in levels], peak


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("destination", nargs="?")
    parser.add_argument("--length", type=float, default=0.5, help="seconds to keep")
    parser.add_argument("--fade", type=float, default=0.12, help="fade-out length in seconds")
    parser.add_argument("--peak", type=float, default=None, help="normalise to this dBFS")
    parser.add_argument("--report", action="store_true", help="print the envelope and stop")
    args = parser.parse_args()

    samples, channels, width, rate, frames = read_wav(args.source)
    print("  in:  %d ch  %d Hz  %d-bit  %.3f s" % (channels, rate, width * 8, frames / rate))

    if args.report:
        levels, _ = envelope(samples, channels, width, rate)
        for index, level in enumerate(levels):
            if index % 2:
                continue
            bar = "#" * max(0, int((level + 60) / 2))
            print("  %5.2fs  %6.1f dB %s" % (index * 0.01, level, bar))
        for threshold in (-20, -30, -40, -50):
            last = 0.0
            for index in range(len(levels) - 1, -1, -1):
                if levels[index] > threshold:
                    last = (index + 1) * 0.01
                    break
            print("  last above %d dB: %.2fs" % (threshold, last))
        return 0

    if not args.destination:
        raise SystemExit("a destination is required unless --report is given")

    keep = min(frames, int(args.length * rate))
    trimmed = samples[: keep * channels]

    fade = min(keep, int(args.fade * rate))
    if fade > 0:
        for i in range(fade):
            frame = keep - fade + i
            # Equal-power rather than linear: a linear ramp on a decaying tail
            # audibly ducks in the middle, because the tail is already falling.
            gain = math.cos(0.5 * math.pi * (i / float(fade)))
            for channel in range(channels):
                index = frame * channels + channel
                trimmed[index] = int(trimmed[index] * gain)

    if args.peak is not None:
        full_scale = float((1 << (width * 8 - 1)) - 1)
        loudest = max(abs(v) for v in trimmed) or 1
        target = full_scale * (10.0 ** (args.peak / 20.0))
        gain = target / loudest
        limit = int(full_scale)
        trimmed = [max(-limit, min(limit, int(v * gain))) for v in trimmed]

    write_wav(args.destination, trimmed, channels, width, rate)
    print("  out: %.3f s  (%.0f ms fade)  ->  %s" % (
        len(trimmed) / channels / rate, args.fade * 1000.0, args.destination
    ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
