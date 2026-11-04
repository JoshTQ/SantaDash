"""
Sleigh Heist sound synthesiser: renders every key in src/shared/Sounds.luau
as a cartoon-style .ogg, made entirely from code (oscillators, noise and
filters), so the audio is original and Josh owns it outright.

    python3 tools/audio/synth.py [out_dir] [Key ...]

Needs numpy and ffmpeg (libvorbis). Output files are named after the sound
keys, so a Studio bulk import gives Sounds with the right names.
"""

import os
import subprocess
import sys
import wave

import numpy as np

SR = 44100
RNG = np.random.default_rng(1225)

# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------


def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def silence(dur):
    return np.zeros(int(dur * SR))


def glide(f0, f1, dur, curve="exp"):
    """A frequency contour from f0 to f1 over dur seconds."""
    n = int(dur * SR)
    x = np.linspace(0, 1, n, endpoint=False)
    if curve == "exp":
        return f0 * (f1 / f0) ** x
    return f0 + (f1 - f0) * x


def osc(freq, dur=None, shape="sine", phase=0.0):
    """freq: number or per-sample array."""
    if np.isscalar(freq):
        freq = np.full(int(dur * SR), float(freq))
    ph = phase + np.cumsum(freq) / SR
    frac = ph % 1.0
    if shape == "sine":
        return np.sin(2 * np.pi * ph)
    if shape == "square":
        return np.where(frac < 0.5, 1.0, -1.0)
    if shape == "saw":
        return 2 * frac - 1
    if shape == "tri":
        return 2 * np.abs(2 * frac - 1) - 1
    if shape == "pulse":  # narrow pulse: reedy, nasal
        return np.where(frac < 0.18, 1.0, -0.22)
    raise ValueError(shape)


def noise(dur):
    return RNG.uniform(-1, 1, int(dur * SR))


def env(n_or_sig, a=0.005, d=0.0, s=1.0, r=0.05):
    """ADSR over the whole length (sustain fills the middle)."""
    n = n_or_sig if isinstance(n_or_sig, int) else len(n_or_sig)
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(0, n - a_n - d_n - r_n)
    e = np.concatenate(
        [
            np.linspace(0, 1, a_n, endpoint=False),
            np.linspace(1, s, d_n, endpoint=False),
            np.full(s_n, s),
            np.linspace(s, 0, r_n),
        ]
    )[:n]
    if len(e) < n:
        e = np.pad(e, (0, n - len(e)))
    return e if isinstance(n_or_sig, int) else n_or_sig * e


def decay(sig, rate):
    return sig * np.exp(-rate * np.arange(len(sig)) / SR)


def fft_filter(sig, lo=None, hi=None, soft=1.3):
    """Smooth band-pass by FFT mask (lo/hi in Hz, either optional)."""
    n = len(sig)
    if n == 0:
        return sig
    spec = np.fft.rfft(sig)
    f = np.fft.rfftfreq(n, 1 / SR)
    mask = np.ones_like(f)
    if lo:
        mask *= 1 / (1 + (lo / np.maximum(f, 1e-3)) ** (2 * soft))
    if hi:
        mask *= 1 / (1 + (f / hi) ** (2 * soft))
    return np.fft.irfft(spec * mask, n)


def resonator(sig, freq, q):
    """Two-pole resonant band-pass; freq may be a per-sample array."""
    n = len(sig)
    freq = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    out = np.zeros(n)
    y1 = y2 = 0.0
    for i in range(n):
        w = 2 * np.pi * freq[i] / SR
        r = np.exp(-w / (2 * q))
        b1 = 2 * r * np.cos(w)
        b2 = -r * r
        y = (1 - r) * sig[i] + b1 * y1 + b2 * y2
        y2, y1 = y1, y
        out[i] = y
    return out


def lowpass_sweep(sig, f_from, f_to):
    """One-pole low-pass whose cutoff glides (for whooshes and wah)."""
    n = len(sig)
    cut = np.geomspace(f_from, f_to, n) if np.isscalar(f_from) else f_from
    a = 1 - np.exp(-2 * np.pi * cut / SR)
    out = np.zeros(n)
    y = 0.0
    for i in range(n):
        y += a[i] * (sig[i] - y)
        out[i] = y
    return out


VOWELS = {  # formant centre frequencies (Hz): cartoon-ish
    "a": (800, 1200, 2600),
    "o": (500, 850, 2500),
    "u": (330, 800, 2300),
    "e": (450, 1900, 2600),
    "i": (300, 2300, 3000),
    "uh": (600, 1050, 2400),
    "oo": (300, 700, 2200),
}


def voice(f0, vowel_track, dur, rough=0.0, breath=0.08, shape="saw"):
    """A cartoon voice: glottal buzz through three formant resonators.
    f0: number or contour; vowel_track: list of (time_frac, vowel)."""
    n = int(dur * SR)
    if np.isscalar(f0):
        f0 = np.full(n, float(f0))
    f0 = f0[:n]
    vib = 1 + 0.012 * np.sin(2 * np.pi * 5.5 * np.arange(n) / SR)
    src = osc(f0 * vib, shape=shape) + breath * noise(n / SR)[:n]
    if rough:
        src *= 1 + rough * np.sin(2 * np.pi * 31 * np.arange(n) / SR)
    # Formant tracks interpolated between vowel targets.
    times = [int(tf * n) for tf, _ in vowel_track] + [n]
    tracks = [np.zeros(n) for _ in range(3)]
    for k, (_, v) in enumerate(vowel_track):
        a, b = times[k], times[k + 1]
        nxt = VOWELS[vowel_track[min(k + 1, len(vowel_track) - 1)][1]]
        for j in range(3):
            tracks[j][a:b] = np.linspace(VOWELS[v][j], nxt[j] if k + 1 < len(vowel_track) else VOWELS[v][j], b - a)
    out = resonator(src, tracks[0], 6) * 1.0 + resonator(src, tracks[1], 8) * 0.6 + resonator(src, tracks[2], 10) * 0.25
    return out


def bell(freq, dur, bright=1.0, decay_rate=3.0):
    """Inharmonic bell partials."""
    t = t_axis(dur)
    parts = [(1, 1.0), (2.0, 0.55), (2.76, 0.45 * bright), (5.4, 0.25 * bright), (8.93, 0.12 * bright)]
    out = np.zeros(len(t))
    for ratio, amp in parts:
        out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t * decay_rate * (0.6 + ratio * 0.35))
    return out * env(len(t), a=0.001, r=0.01)


def jingle_hit(dur=0.18, base=None):
    """One shake of a cluster of tiny sleigh bells."""
    out = silence(dur)
    for _ in range(6):
        f = base or RNG.uniform(2600, 4200)
        start = RNG.uniform(0, 0.025)
        b = bell(f * RNG.uniform(0.92, 1.08), dur - start, bright=0.7, decay_rate=14)
        place(out, b * RNG.uniform(0.4, 1), start)
    shimmer = decay(fft_filter(noise(dur), lo=5000), 30) * 0.25
    return out + shimmer


def place(dst, src, at):
    i = int(at * SR)
    if i >= len(dst):
        return dst
    end = min(len(dst), i + len(src))
    dst[i:end] += src[: end - i]
    return dst


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def cat(*parts):
    return np.concatenate(parts)


def reverb(sig, size=1.2, wet=0.3):
    ir_t = t_axis(size)
    ir = noise(size) * np.exp(-ir_t * 5 / size)
    ir = fft_filter(ir, hi=6000)
    ir /= np.sqrt(np.sum(ir**2)) + 1e-9
    n = len(sig) + len(ir)
    wet_sig = np.fft.irfft(np.fft.rfft(sig, n) * np.fft.rfft(ir, n), n)
    return mix(sig * (1 - wet), wet_sig * wet * 1.6)


def drive(sig, amount=2.0):
    return np.tanh(sig * amount) / np.tanh(amount)


def thump(f0=90, f1=40, dur=0.25, click=0.3):
    t = t_axis(dur)
    body = osc(glide(f0, f1, dur), shape="sine") * np.exp(-t * 14)
    c = decay(fft_filter(noise(0.02), lo=1500), 200) * click
    return mix(body, c)


def click(dur=0.012, lo=2000, amp=1.0):
    return decay(fft_filter(noise(dur), lo=lo), 400) * amp


def make_loop(sig, fade=0.4):
    """Seamless loop: crossfade the tail into the head."""
    f = int(fade * SR)
    head, body, tail = sig[:f], sig[f:-f] if f else sig, sig[-f:]
    x = np.linspace(0, 1, f)
    blended = tail * np.cos(x * np.pi / 2) + head * np.sin(x * np.pi / 2)
    return cat(body, blended)


# ---------------------------------------------------------------------------
# Music helpers
# ---------------------------------------------------------------------------

NOTE = {"C": -9, "C#": -8, "Db": -8, "D": -7, "D#": -6, "Eb": -6, "E": -5, "F": -4, "F#": -3, "Gb": -3, "G": -2, "G#": -1, "Ab": -1, "A": 0, "A#": 1, "Bb": 1, "B": 2}


def hz(name):
    """'A4', 'C#5' -> Hz."""
    letter = name[:-1]
    octave = int(name[-1])
    return 440.0 * 2 ** ((NOTE[letter] + (octave - 4) * 12) / 12)


def pluck(freq, dur, bright=0.5):
    """Pizzicato / plucked string (Karplus-Strong)."""
    n = int(dur * SR)
    period = max(2, int(SR / freq))
    buf = RNG.uniform(-1, 1, period)
    out = np.zeros(n)
    damp = 0.5 + 0.49 * bright
    for i in range(n):
        out[i] = buf[i % period]
        j = (i + 1) % period
        buf[i % period] = damp * 0.5 * (buf[i % period] + buf[j]) + (1 - damp) * buf[i % period] * 0.0
    return env(out, a=0.002, r=0.02)


def ks_fast(freq, dur, decay_s=0.6):
    """Cheap plucked tone: harmonics with fast decay (vectorised)."""
    t = t_axis(dur)
    out = np.zeros(len(t))
    for h in range(1, 7):
        out += (0.7**h) * np.sin(2 * np.pi * freq * h * t) * np.exp(-t * (1 / decay_s) * (1 + h * 0.6))
    return env(out, a=0.002, r=0.03)


def brass(freq, dur, bright=0.6):
    t = t_axis(dur)
    f = np.full(len(t), freq) * (1 + 0.006 * np.sin(2 * np.pi * 5 * t))
    raw = osc(f, shape="saw")
    cut = freq * (2 + 6 * bright * np.clip(t / 0.08, 0, 1))
    return env(lowpass_sweep(raw, cut, None), a=0.03, d=0.08, s=0.8, r=0.08)


def bassoon(freq, dur):
    raw = osc(freq, dur, shape="pulse")
    return env(fft_filter(raw, hi=freq * 4), a=0.02, s=0.9, r=0.06)


def marimba(freq, dur):
    t = t_axis(dur)
    return (np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(2 * np.pi * freq * 4 * t) * np.exp(-t * 30)) * np.exp(-t * 7)


def sequence(notes, bpm, instrument, total_beats):
    """notes: list of (beat, length_beats, note_name or Hz, gain)."""
    beat = 60 / bpm
    out = silence(total_beats * beat + 2)
    for start, length, note, gain in notes:
        f = hz(note) if isinstance(note, str) else note
        place(out, instrument(f, length * beat) * gain, start * beat)
    return out[: int(total_beats * beat * SR)]


def loop_wrap(sig, total):
    """Fold anything past `total` samples (ringing tails) back to the start."""
    out = sig[:total].copy()
    tail = sig[total:]
    out[: len(tail)] += tail[: len(out)]
    return out


def music(parts, bpm, beats):
    beat = 60 / bpm
    total = int(beats * beat * SR)
    mixed = silence(beats * beat + 2)
    for notes, inst, gain in parts:
        b = beat
        seg = silence(beats * beat + 2)
        for start, length, note, g in notes:
            f = hz(note) if isinstance(note, str) else note
            place(seg, inst(f, length * b) * g, start * b)
        mixed[: len(seg)] += seg * gain
    return loop_wrap(mixed, total)


def drums(pattern, bpm, beats, kit):
    """pattern: list of (beat, name)."""
    beat = 60 / bpm
    out = silence(beats * beat + 1)
    for b, name in pattern:
        place(out, kit[name](), b * beat)
    return loop_wrap(out, int(beats * beat * SR))


KIT = {
    "kick": lambda: thump(110, 45, 0.25, 0.2),
    "snare": lambda: mix(decay(fft_filter(noise(0.18), lo=1200, hi=8000), 22) * 0.6, osc(190, 0.1) * np.exp(-t_axis(0.1) * 30) * 0.4),
    "hat": lambda: decay(fft_filter(noise(0.05), lo=7000), 80) * 0.35,
    "jingle": lambda: jingle_hit(0.2) * 0.4,
    "tick": lambda: click(0.015, 3000, 0.6),
    "tock": lambda: decay(osc(900, 0.04), 120) * 0.5,
}


# ---------------------------------------------------------------------------
# The sounds, by key
# ---------------------------------------------------------------------------

S = {}


def sound(fn):
    S[fn.__name__] = fn
    return fn


def honk(dur=0.55, pitch=1.0):
    f = glide(210 * pitch, 196 * pitch, dur)
    tone = osc(f, shape="saw") + 0.8 * osc(f * 1.26, shape="saw") + 0.4 * osc(f * 0.5, shape="square")
    tone = resonator(tone, 700, 3) + resonator(tone, 1500, 5) * 0.5
    return drive(env(tone, a=0.02, s=1, r=0.06) * 3, 1.5)


@sound
def SleighHorn():
    return cat(honk(0.75), silence(0.05))


@sound
def LastCall():
    return cat(honk(0.22, 1.06), silence(0.07), honk(0.5, 1.06), silence(0.05))


@sound
def CountdownTick():
    return mix(jingle_hit(0.35) * 0.8, bell(1568, 0.5, bright=0.5, decay_rate=6) * 0.5)


@sound
def SleighTakeoff():
    d = 1.6
    wh = noise(d)
    wh = lowpass_sweep(wh, 300, 5000) * env(int(d * SR), a=0.5, r=0.6)
    bells = silence(d)
    for k in range(10):
        place(bells, jingle_hit(0.25) * (0.5 + k * 0.05), 0.08 + k * 0.12)
    rise = osc(glide(300, 1200, 1.0), shape="sine") * env(int(SR * 1.0), a=0.2, r=0.4) * 0.25
    return mix(wh * 0.6, bells, place(silence(d), rise, 0.2))


@sound
def SleighLand():
    snow = decay(fft_filter(noise(0.5), hi=1200), 9) * 0.5
    return mix(thump(80, 38, 0.4, 0.1), snow, place(silence(0.6), jingle_hit(0.3) * 0.5, 0.05))


@sound
def FlightBells():
    d = 2.0  # galloping: da-da-DUM, twice a second
    out = silence(d + 0.4)
    for beat in range(4):
        b = beat * 0.5
        for off, g in ((0, 0.5), (0.12, 0.6), (0.25, 1.0)):
            place(out, jingle_hit(0.3) * g, b + off)
    return loop_wrap(out, int(d * SR))


@sound
def KrampusComing():
    d = 1.6
    f = cat(glide(90, 140, 0.4), glide(140, 70, 1.2))
    roar = voice(f, [(0, "a"), (0.5, "o"), (0.9, "u")], d, rough=0.6, breath=0.4)
    roar = drive(env(roar, a=0.08, r=0.4) * 4, 2.5)
    hit = mix(bell(220, 1.5, 1.2, 2.5), bell(233, 1.5, 1.2, 2.5)) * 0.4
    return reverb(mix(roar, hit, jingle_hit(0.4)), 1.2, 0.25)


@sound
def KrampusBells():
    d = 2.0  # heavy, rhythmic shake: he lumbers
    out = silence(d + 0.4)
    for b in np.arange(0, d, 0.25):
        g = 1.0 if (b * 4) % 2 == 0 else 0.6
        place(out, jingle_hit(0.3, base=None) * g, b + RNG.uniform(0, 0.015))
        if (b * 4) % 4 == 0:
            place(out, bell(880, 0.4, 0.8, 7) * 0.25, b)
    return loop_wrap(out, int(d * SR))


@sound
def KrampusHeartbeat():
    d = 0.9
    out = silence(d)
    place(out, thump(70, 40, 0.18, 0.05), 0.0)
    place(out, thump(60, 35, 0.2, 0.05) * 0.75, 0.22)
    return fft_filter(out, hi=400)


@sound
def KrampusSnatch():
    # "HO HO HO!" deep, then a sack swish.
    parts = []
    for k, f in enumerate((120, 110, 100)):
        syl = voice(glide(f * 1.1, f * 0.9, 0.22), [(0, "o"), (0.6, "u")], 0.22, rough=0.4, breath=0.25)
        parts += [env(syl, a=0.02, r=0.06), silence(0.08)]
    laugh = drive(cat(*parts) * 3, 2)
    swish = lowpass_sweep(noise(0.35), 400, 4000) * env(int(0.35 * SR), a=0.1, r=0.2)
    return reverb(cat(laugh, swish * 0.6), 0.8, 0.2)


@sound
def KrampusSniff():
    out = silence(0.75)
    for k, at in enumerate((0.0, 0.18, 0.36)):
        s = fft_filter(noise(0.12), lo=1800 + k * 300, hi=5000) * env(int(0.12 * SR), a=0.04, r=0.05)
        place(out, s, at)
    place(out, decay(fft_filter(noise(0.25), lo=300, hi=1500), 10) * 0.5, 0.5)  # snort
    return out


@sound
def BellBonk():
    return mix(bell(660, 1.2, 1.4, 3), bell(990, 1.0, 1.0, 4) * 0.5, click(0.02, 1000, 0.6))


@sound
def KrampusDizzy():
    d = 1.6
    out = silence(d)
    for k in range(6):
        at = k * 0.24
        chirp = osc(cat(glide(2400, 3600, 0.06), glide(3600, 2600, 0.06)), shape="sine")
        place(out, env(chirp, a=0.005, r=0.02) * 0.5, at)
        place(out, env(chirp, a=0.005, r=0.02) * 0.35, at + 0.12)
    return out


@sound
def Boing():
    d = 0.7
    t = t_axis(d)
    f = 180 * (1 + 0.5 * t / d) * (1 + 0.35 * np.sin(2 * np.pi * 14 * t) * np.exp(-t * 4))
    return env(osc(f, shape="sine") + 0.3 * osc(f * 2, shape="tri"), a=0.003, r=0.15) * np.exp(-t * 2.5)


@sound
def Wiggle():
    d = 0.16
    f = glide(700, 1300, d) * (1 + 0.04 * np.sin(2 * np.pi * 40 * t_axis(d)))
    return env(osc(f, shape="tri") + 0.3 * osc(f * 2), a=0.01, r=0.04)


@sound
def KrampusTease():
    out = silence(2.6)
    for k in range(7):
        place(out, jingle_hit(0.3) * (0.5 + 0.5 * np.sin(k)), 0.1 + k * 0.28)
    return reverb(fft_filter(out, hi=2200), 2.0, 0.6)


@sound
def KrampusStomp():
    boom = thump(55, 25, 1.2, 0.5) * 1.2
    rumble = decay(fft_filter(noise(1.5), hi=200), 3) * 0.6
    return reverb(mix(boom, rumble), 1.0, 0.2)


@sound
def IceCrack():
    d = 1.2
    out = silence(d)
    at = 0.0
    while at < d - 0.1:
        c = decay(fft_filter(noise(0.03), lo=2500), 120) * RNG.uniform(0.3, 1)
        place(out, c, at)
        place(out, decay(osc(RNG.uniform(1500, 3500), 0.08), 60) * 0.2, at)
        at += RNG.exponential(0.035)
    return out * np.exp(-t_axis(d) * 1.5)


@sound
def PresentGrab():
    d = 0.4
    out = silence(d)
    for _ in range(14):
        place(out, decay(fft_filter(noise(0.02), lo=2500, hi=9000), 150) * RNG.uniform(0.2, 0.6), RNG.uniform(0, 0.18))
    pop = osc(glide(900, 300, 0.06), shape="sine") * np.exp(-t_axis(0.06) * 40)
    place(out, pop, 0.2)
    place(out, click(0.01, 1500, 0.4), 0.2)
    return out


@sound
def NaughtyListGrab():
    d = 1.6
    rattle = silence(d)
    for _ in range(30):
        place(rattle, bell(RNG.uniform(1800, 3200), 0.12, 0.6, 30) * RNG.uniform(0.2, 0.5), RNG.uniform(0, 0.5))
    chord = silence(d)
    for f in (hz("D3"), hz("F3"), hz("Ab3"), hz("D4")):
        place(chord, brass(f, 1.0) * 0.3, 0.45)
    return mix(rattle, reverb(chord, 0.8, 0.3))


@sound
def SackFull():
    grunt = voice(glide(170, 120, 0.25), [(0, "uh")], 0.25, breath=0.3)
    return mix(env(grunt, a=0.01, r=0.08), place(silence(0.5), thump(100, 50, 0.25, 0.3), 0.18))


@sound
def JingleGain():
    out = silence(0.4)
    place(out, bell(2637, 0.3, 0.6, 12) * 0.6, 0)
    place(out, bell(3136, 0.3, 0.6, 12) * 0.5, 0.06)
    return out


@sound
def Bank():
    out = silence(1.1)
    place(out, click(0.02, 800, 0.8), 0.0)
    for _ in range(8):
        place(out, bell(RNG.uniform(3000, 4500), 0.15, 0.5, 25) * 0.25, RNG.uniform(0.02, 0.2))
    place(out, bell(2093, 0.9, 0.8, 4) * 0.8, 0.22)
    place(out, bell(2637, 0.9, 0.8, 4) * 0.5, 0.22)
    place(out, thump(120, 70, 0.15, 0.4) * 0.6, 0.18)
    return out


@sound
def SackSpill():
    out = silence(1.0)
    at = 0.0
    for k in range(6):
        place(out, thump(RNG.uniform(140, 260), RNG.uniform(60, 120), 0.15, 0.6) * (1 - k * 0.1), at)
        at += RNG.uniform(0.08, 0.15)
    place(out, osc(glide(500, 200, 0.5), shape="tri") * env(int(0.5 * SR), a=0.01, r=0.1) * 0.2, 0.1)
    return out


@sound
def ParentSnore():
    d = 3.6
    t = t_axis(d)
    out = silence(d)
    # Inhale: a rattly snore (low buzz through 'o'), exhale: a little whistle.
    inhale_d = 1.5
    buzz = voice(glide(70, 85, inhale_d), [(0, "o"), (1, "uh")], inhale_d, rough=0.9, breath=0.8, shape="pulse")
    buzz *= np.sin(np.linspace(0, np.pi, len(buzz))) ** 1.5
    place(out, buzz * 1.2, 0.2)
    exhale_d = 1.1
    wh = osc(glide(900, 650, exhale_d), shape="sine") * np.sin(np.linspace(0, np.pi, int(exhale_d * SR))) * 0.12
    air = fft_filter(noise(exhale_d), lo=400, hi=2000) * np.sin(np.linspace(0, np.pi, int(exhale_d * SR))) * 0.15
    place(out, mix(wh, air), 2.0)
    return out * 0.9


@sound
def ParentWake():
    # "Hm? Huh?! Who's there?" as cartoon gibberish with the right melody.
    parts = [
        env(voice(glide(180, 200, 0.25), [(0, "u")], 0.25, breath=0.2), a=0.02, r=0.05),
        silence(0.12),
        env(voice(glide(170, 300, 0.3), [(0, "uh"), (0.6, "a")], 0.3, breath=0.15), a=0.02, r=0.05),
        silence(0.18),
        env(voice(glide(230, 260, 0.18), [(0, "oo"), (0.7, "u")], 0.18), a=0.01, r=0.03),
        env(voice(glide(260, 220, 0.12), [(0, "e")], 0.12), a=0.01, r=0.03),
        env(voice(glide(240, 330, 0.35), [(0, "e"), (0.5, "a")], 0.35), a=0.01, r=0.08),
    ]
    return drive(cat(*parts) * 2, 1.4)


@sound
def LightsOn():
    out = silence(1.1)
    place(out, click(0.015, 2000, 1.0), 0)
    place(out, click(0.01, 4000, 0.5), 0.015)
    place(out, marimba(hz("E5"), 0.4) * 0.6, 0.18)
    place(out, marimba(hz("C5"), 0.6) * 0.6, 0.45)
    return out


@sound
def NoiseWarn():
    a = env(osc(glide(900, 1400, 0.12), shape="tri"), a=0.005, r=0.03)
    b = env(osc(glide(1400, 900, 0.14), shape="tri"), a=0.005, r=0.04)
    return cat(a, silence(0.04), b) * 0.8


@sound
def NoiseFull():
    d = 1.4
    t = t_axis(d)
    f = 650 + 250 * np.sign(np.sin(2 * np.pi * 3.5 * t))
    s = osc(f, shape="square") * 0.5 + osc(f * 1.5, shape="tri") * 0.3
    return env(fft_filter(s, hi=3000), a=0.01, r=0.15)


def dog_voice(f0, dur, vowel=("a", "u"), rough=0.5):
    return voice(glide(f0 * 1.3, f0 * 0.8, dur), [(0, vowel[0]), (0.5, vowel[1])], dur, rough=rough, breath=0.35)


@sound
def CorgiGrowl():
    d = 1.0
    g = voice(np.full(int(d * SR), 150.0), [(0, "uh"), (0.5, "u")], d, rough=1.0, breath=0.4, shape="pulse")
    g *= 0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 22 * t_axis(d)))
    return env(g, a=0.1, r=0.2)


@sound
def CorgiWoof():
    out = silence(0.7)
    place(out, drive(env(dog_voice(520, 0.13), a=0.005, r=0.04) * 3, 2), 0)
    place(out, drive(env(dog_voice(560, 0.12), a=0.005, r=0.04) * 3, 2), 0.2)
    return out


@sound
def TinDogWhirr():
    d = 1.0
    out = silence(d)
    rate = 18
    for k in range(int(d * rate)):
        at = k / rate
        place(out, mix(click(0.008, 3000, 0.6), decay(osc(2400, 0.02), 200) * 0.3), at)
    whirr = osc(glide(300, 420, d), shape="saw") * 0.08
    return mix(out, fft_filter(whirr, hi=2000))


@sound
def TinDogBonk():
    d = 1.6
    out = silence(d)
    place(out, mix(bell(520, 0.6, 1.6, 6), bell(740, 0.6, 1.4, 7)) * 0.7, 0)
    sp = osc(220 * (1 + 0.3 * np.sin(2 * np.pi * 18 * t_axis(0.5)) * np.exp(-t_axis(0.5) * 5)), shape="tri") * np.exp(-t_axis(0.5) * 5) * 0.4
    place(out, sp, 0.02)
    at, gap = 0.5, 0.05
    while at < d - 0.05:  # clockwork running down
        place(out, click(0.01, 2500, 0.5), at)
        at += gap
        gap *= 1.25
    return out


@sound
def DoorOpen():
    d = 0.9
    out = silence(d)
    at, rate = 0.05, 40.0
    while at < d - 0.1:  # creak: a slowing stick-slip
        place(out, resonator(click(0.006, 200, 1.0), 900, 12) * 3, at)
        at += 1 / rate
        rate *= 0.985
    return out * np.sin(np.linspace(0, np.pi, len(out))) ** 0.5


@sound
def DoorClose():
    return mix(thump(130, 70, 0.3, 0.6), place(silence(0.35), click(0.01, 2500, 0.6), 0.05))


def slide_whistle(f0, f1, dur):
    f = glide(f0, f1, dur) * (1 + 0.02 * np.sin(2 * np.pi * 6 * t_axis(dur)))
    tone = osc(f, shape="sine") + 0.05 * fft_filter(noise(dur), lo=1000, hi=4000)
    return env(tone, a=0.03, r=0.08)


@sound
def ChimneySlide():
    return mix(slide_whistle(1600, 350, 0.75), place(silence(1.0), thump(90, 45, 0.25, 0.3) * 0.6, 0.7))


@sound
def ChimneyClimb():
    return slide_whistle(350, 1600, 0.65)


@sound
def HideIn():
    out = silence(0.5)
    place(out, DoorOpen()[: int(0.25 * SR)] * 0.5, 0)
    place(out, thump(160, 90, 0.2, 0.5), 0.22)
    return out


@sound
def HideOut():
    out = silence(0.6)
    place(out, click(0.01, 2000, 0.5), 0)
    place(out, DoorOpen()[: int(0.45 * SR)] * 0.7, 0.03)
    return out


@sound
def Gasp():
    d = 0.55
    g = voice(glide(260, 420, d), [(0, "a"), (1, "a")], d, breath=1.5)
    air = fft_filter(noise(d), lo=800, hi=5000) * 0.5
    return env(g * 0.6 + air, a=0.15, r=0.12)


@sound
def BreathStrain():
    d = 0.7
    hum = voice(np.full(int(d * SR), 200.0), [(0, "u")], d, breath=0.05)
    hum *= 0.6 + 0.4 * np.sin(2 * np.pi * 9 * t_axis(d))
    return env(hum, a=0.05, r=0.1)


@sound
def CocoaSlurp():
    d = 0.9
    s = fft_filter(noise(d), lo=500, hi=6000)
    s = lowpass_sweep(s, 600, 4000) * env(int(d * SR), a=0.1, r=0.25)
    out = s * 0.6
    for k in range(4):
        place(out, osc(glide(300, 700, 0.05)) * np.exp(-t_axis(0.05) * 30) * 0.4, 0.15 + k * 0.15)
    place(out, env(voice(glide(260, 200, 0.3), [(0, "a")], 0.3), a=0.02, r=0.1) * 0.5, 0.95)  # "ahh"
    return out


@sound
def VaultOpen():
    out = silence(2.0)
    place(out, thump(70, 35, 0.5, 0.8) * 1.2, 0)
    for k in range(6):
        place(out, mix(click(0.02, 1500, 0.7), decay(osc(1200 + k * 80, 0.05), 80) * 0.3), 0.3 + k * 0.09)
    place(out, DoorOpen() * 0.6, 0.9)
    place(out, bell(220, 1.0, 1.0, 3) * 0.3, 0.25)
    return reverb(out, 0.7, 0.2)


@sound
def Nope():
    a = env(fft_filter(osc(140, 0.12, shape="square"), hi=2000), a=0.005, r=0.02)
    return cat(a, silence(0.05), a * 0.8)


@sound
def Splash():
    d = 1.0
    main = decay(lowpass_sweep(noise(d), 6000, 500), 4) * 0.9
    out = main
    for _ in range(10):
        place(out, osc(glide(RNG.uniform(900, 1800), RNG.uniform(1800, 3000), 0.04)) * np.exp(-t_axis(0.04) * 50) * 0.3, RNG.uniform(0.1, 0.7))
    return out


@sound
def HoopBoost():
    out = silence(0.9)
    for k, n in enumerate(("C6", "E6", "G6", "C7")):
        place(out, bell(hz(n), 0.5, 0.5, 8) * 0.5, k * 0.06)
    wh = lowpass_sweep(noise(0.5), 1000, 8000) * env(int(0.5 * SR), a=0.1, r=0.3) * 0.4
    return mix(out, wh)


@sound
def PolisherHum():
    d = 2.0
    t = t_axis(d)
    hum = sum(np.sin(2 * np.pi * 60 * h * t) / h for h in (1, 2, 3, 5)) * 0.4
    brush = fft_filter(noise(d), lo=800, hi=3000) * (0.6 + 0.4 * np.sin(2 * np.pi * 4 * t)) * 0.25
    return make_loop(cat(hum + brush, (hum + brush)[: int(0.3 * SR)]), 0.3)


@sound
def PolisherScoop():
    d = 0.7
    wh = lowpass_sweep(noise(d), 400, 6000) * env(int(d * SR), a=0.2, r=0.3)
    return mix(wh, place(silence(d + 0.3), decay(fft_filter(noise(0.4), hi=1500), 8) * 0.6, d - 0.1))


@sound
def NightAmbience():
    d = 20.0
    t = t_axis(d)
    wind = fft_filter(noise(d), lo=150, hi=900)
    wind *= 0.5 + 0.35 * np.sin(2 * np.pi * t / 7.0) + 0.15 * np.sin(2 * np.pi * t / 2.9)
    out = wind * 0.6
    for k in range(5):  # far-off chimes
        at = RNG.uniform(1, d - 3)
        place(out, reverb(bell(hz(RNG.choice(["E6", "G6", "B6", "D7"])), 1.5, 0.4, 3), 1.5, 0.7) * 0.08, at)
    return make_loop(out, 1.5)


@sound
def SneakMusic():
    bpm, beats = 104, 32  # tiptoe pizzicato in E minor
    bass = []
    walk = ["E2", "G2", "B2", "G2", "C3", "B2", "A2", "B2"]
    for bar in range(8):
        root = walk[bar]
        for b in (0, 2):
            bass.append((bar * 4 + b, 0.5, root, 0.9))
    mel = []
    phrase = [(0, "B4"), (1, "C5"), (1.5, "B4"), (2, "A4"), (3, "G4"), (4, "E4"), (5, "F#4"), (6, "G4"), (7, "B4")]
    for rep in range(4):
        for b, n in phrase:
            mel.append((rep * 8 + b, 0.4, n, 0.55 if b % 1 else 0.7))
    high = [(rep * 8 + 7.5, 0.3, "E5", 0.4) for rep in range(4)]
    tune = music([(bass, ks_fast, 0.9), (mel, lambda f, d: ks_fast(f, d, 0.35), 0.7), (high, marimba, 0.6)], bpm, beats)
    perc = drums([(b + 0.5, "tick") for b in range(beats)], bpm, beats, KIT)
    return tune + perc * 0.5


@sound
def HurryMusic():
    bpm, beats = 168, 32  # galloping chase in D major
    chords = ["D", "D", "G", "A", "D", "B", "G", "A"]
    roots = {"D": "D2", "G": "G2", "A": "A2", "B": "B1"}
    bass = []
    for bar, c in enumerate(chords):
        for b in range(4):
            bass.append((bar * 4 + b, 0.45, roots[c] if b % 2 == 0 else roots[c][:-1] + "3", 0.8))
    mel_notes = ["F#4", "A4", "D5", "A4", "B4", "G4", "E4", "A4", "F#4", "A4", "D5", "F#5", "D5", "B4", "C#5", "E5"]
    mel = [(k * 2, 1.6, n, 0.5) for k, n in enumerate(mel_notes)]
    pat = []
    for b in range(beats):
        pat.append((b, "kick" if b % 2 == 0 else "snare"))
        pat.append((b + 0.5, "hat"))
        pat.append((b, "jingle"))
    tune = music([(bass, lambda f, d: bassoon(f, d), 0.6), (mel, lambda f, d: brass(f, d), 0.45)], bpm, beats)
    return tune + drums(pat, bpm, beats, KIT) * 0.7


@sound
def KrampusMusic():
    bpm, beats = 132, 32  # spooky-silly: bassoon oompah in C minor with tick-tock
    roots = ["C2", "G1", "Ab1", "G1"]
    bass = []
    for bar in range(8):
        r = roots[bar % 4]
        for b in range(4):
            bass.append((bar * 4 + b, 0.4, r if b % 2 == 0 else r[:-1] + str(int(r[-1]) + 1), 0.8))
    mel_notes = ["C4", "Eb4", "G4", "F#4", "G4", "Ab4", "G4", "Eb4", "C4", "D4", "Eb4", "B3", "C4", "G3", "C4", "C4"]
    mel = [(k * 2, 1.5, n, 0.55) for k, n in enumerate(mel_notes)]
    pat = [(b, "tick" if b % 2 == 0 else "tock") for b in range(beats)] + [(b, "kick") for b in range(0, beats, 2)]
    tune = music([(bass, bassoon, 0.7), (mel, lambda f, d: bassoon(f * 2, d), 0.35)], bpm, beats)
    return tune + drums(pat, bpm, beats, KIT) * 0.6


@sound
def LobbyMusic():
    bpm, beats = 120, 32  # cheerful bell carol in F major
    chords = [("F3", "A3", "C4"), ("Bb2", "D3", "F3"), ("C3", "E3", "G3"), ("F3", "A3", "C4")] * 2
    pad = []
    for bar, ch in enumerate(chords):
        for n in ch:
            pad.append((bar * 4, 3.8, n, 0.25))
    mel_notes = ["A4", "A4", "A4", None, "A4", "A4", "A4", None, "A4", "C5", "F4", "G4", "A4", None, None, None]
    mel = [(k * 2 if k < 16 else k, 0.9, n, 0.6) for k, n in enumerate(mel_notes) if n]
    # A cheerful own tune (not a carol melody): bounce on chord tones.
    mel = []
    tones = ["C5", "A4", "F4", "A4", "D5", "Bb4", "F4", "Bb4", "E5", "C5", "G4", "C5", "F5", "C5", "A4", "F4"]
    for k, n in enumerate(tones):
        mel.append((k * 2, 0.9, n, 0.55))
        mel.append((k * 2 + 1, 0.5, n, 0.3))
    pat = [(b, "jingle") for b in range(beats)] + [(b, "kick") for b in range(0, beats, 2)] + [(b + 1, "snare") for b in range(0, beats, 2)]
    tune = music([(pad, lambda f, d: env(osc(f, d, "tri"), a=0.2, r=0.5), 0.6), (mel, lambda f, d: bell(f, d, 0.5, 5), 0.5)], bpm, beats)
    return tune + drums(pat, bpm, beats, KIT) * 0.5


@sound
def ResultsWin():
    out = silence(2.2)
    for k, n in enumerate(("C4", "E4", "G4")):
        place(out, brass(hz(n), 0.16) * 0.5, k * 0.13)
    for n in ("C4", "E4", "G4", "C5"):
        place(out, brass(hz(n), 1.1) * 0.35, 0.42)
    place(out, jingle_hit(0.4), 0.42)
    return reverb(out, 1.0, 0.25)


@sound
def ResultsMiss():
    # "Wah wah wah waaah": a muted trombone slide down.
    out = []
    for n, d in (("D4", 0.4), ("C#4", 0.4), ("C4", 0.4), ("B3", 1.3)):
        t = t_axis(d)
        vib = 0.025 * np.sin(2 * np.pi * 6 * t) * np.clip((t - 0.3) / 0.3, 0, 1) if d > 1 else 0 * t
        tone = osc(hz(n) * (1 + vib), shape="saw")
        wah = lowpass_sweep(tone, np.geomspace(350, 1800, len(t)), None)
        out.append(env(wah, a=0.03, r=0.15))
        out.append(silence(0.05))
    return cat(*out)


# ---------------------------------------------------------------------------
# Round 2 (Josh's Redo marks, 4 Nov): a more human voice, fun horns, no
# metal clang in the music. Later definitions replace the first versions.
# ---------------------------------------------------------------------------

# Male-ish formants (Hz) and bandwidths for the human voice model.
FORMANTS = {
    "a": ((730, 80), (1090, 90), (2440, 120), (3400, 150)),
    "ah": ((700, 80), (1220, 90), (2600, 120), (3400, 150)),
    "uh": ((640, 80), (1190, 90), (2390, 120), (3400, 150)),
    "o": ((570, 70), (840, 80), (2410, 120), (3400, 150)),
    "u": ((440, 70), (1020, 80), (2240, 120), (3400, 150)),
    "oo": ((300, 60), (870, 80), (2240, 120), (3400, 150)),
    "e": ((530, 70), (1840, 90), (2480, 120), (3500, 150)),
    "i": ((270, 60), (2290, 100), (3010, 130), (3700, 150)),
    "m": ((250, 60), (1200, 200), (2200, 250), (3300, 300)),  # closed lips, nasal
    "w": ((300, 60), (610, 80), (2200, 150), (3300, 200)),
    "h": ((700, 200), (1300, 250), (2500, 300), (3500, 300)),
}


def smooth_noise(n, rate_hz, amount):
    """A slow random wobble (for jitter / shimmer): values around 0."""
    k = max(2, int(n * rate_hz / SR) + 2)
    pts = RNG.normal(0, amount, k)
    return np.interp(np.linspace(0, k - 1, n), np.arange(k), pts)


def glottal(f0, n, jitter=0.012, shimmer=0.08, tension=0.6):
    """Rosenberg glottal flow derivative with jitter and shimmer: a far more
    human buzz than a saw wave. tension 0 (lax) .. 1 (pressed)."""
    f = f0 * (1 + smooth_noise(n, 30, jitter) + smooth_noise(n, 4, jitter * 1.5))
    ph = np.cumsum(f) / SR
    frac = ph % 1.0
    op = 0.65 - 0.25 * tension  # open phase
    rise = op * 0.7
    flow = np.where(
        frac < rise,
        0.5 * (1 - np.cos(np.pi * frac / rise)),
        np.where(frac < op, np.cos(0.5 * np.pi * (frac - rise) / (op - rise)), 0.0),
    )
    d = np.diff(flow, prepend=flow[0])
    d /= np.max(np.abs(d)) or 1
    amp = 1 + smooth_noise(n, 25, shimmer)
    return d * amp, flow


def formant_bank(src, vowels_at, n, shift=1.0):
    """Parallel formant resonators following a vowel track [(t_frac, vowel)]."""
    times = [int(tf * n) for tf, _ in vowels_at] + [n]
    out = np.zeros(n)
    gains = (1.0, 0.55, 0.3, 0.12)
    for j in range(4):
        fr = np.zeros(n)
        bw = np.zeros(n)
        for k, (_, v) in enumerate(vowels_at):
            a, b = times[k], times[k + 1]
            cur = FORMANTS[v][j]
            nxt = FORMANTS[vowels_at[k + 1][1]][j] if k + 1 < len(vowels_at) else cur
            # hold the vowel, then glide to the next over the last 35%
            hold = a + int((b - a) * 0.65)
            fr[a:hold] = cur[0]
            fr[hold:b] = np.linspace(cur[0], nxt[0], b - hold)
            bw[a:b] = cur[1]
        fr *= shift
        y = np.zeros(n)
        y1 = y2 = 0.0
        for i in range(n):
            r = np.exp(-np.pi * bw[i] / SR)
            c = 2 * r * np.cos(2 * np.pi * fr[i] / SR)
            yy = (1 - r) * src[i] + c * y1 - r * r * y2
            y2, y1 = y1, yy
            y[i] = yy
        out += y * gains[j]
    return out


def syllable(dur, f0_from, f0_to, vowels, breath=0.25, h_onset=0.0, shift=1.0, tension=0.6, fry=0.0, curve=None):
    """One human-ish voiced syllable: glottal buzz + breath through formants.
    h_onset: seconds of breathy 'h' at the start. fry: vocal-fry growl 0..1."""
    n = int(dur * SR)
    x = np.linspace(0, 1, n)
    contour = curve(x) if curve else np.sin(x * np.pi) * 0.25 + x
    f0 = f0_from + (f0_to - f0_from) * np.clip(contour, 0, 1.2)
    buzz, flow = glottal(f0, n, tension=tension)
    if fry:
        sub = glottal(f0 * 0.5, n, jitter=0.04, shimmer=0.3)[0]
        buzz = buzz + fry * sub * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * f0 * 0.5 * np.arange(n) / SR)))
    asp = fft_filter(noise(dur), lo=400, hi=7000)[:n] * (0.4 + flow)
    voiced = np.ones(n)
    h = int(h_onset * SR)
    if h:
        voiced[:h] = np.linspace(0, 1, h) ** 2
    src = buzz * voiced + asp * (breath + (1 - voiced) * 1.2)
    out = formant_bank(src, vowels, n, shift)
    return env(out, a=0.012, r=min(0.06, dur / 3))


def human(parts, shift=1.0, room=0.12):
    """parts: syllables and silences (arrays). A touch of room so it isn't dry."""
    return reverb(cat(*parts), 0.5, room) if room else cat(*parts)


@sound
def KrampusSnatch():
    # "Mwa-ha-ha-ha-HAAA!" A big villain laugh: breathy h's, falling pitch,
    # uneven timing, a little growl, and a gasp of air at the end.
    parts = [syllable(0.24, 125, 150, [(0, "m"), (0.25, "ah")], breath=0.15, shift=0.9, fry=0.25), silence(0.05)]
    for k, (d, f) in enumerate(((0.15, 150), (0.14, 140), (0.15, 132), (0.13, 124))):
        parts.append(syllable(d, f + 12, f - 10, [(0, "ah")], breath=0.3, h_onset=0.045, shift=0.9, fry=0.2, tension=0.7))
        parts.append(silence(RNG.uniform(0.06, 0.09)))
    parts.append(
        syllable(0.55, 165, 95, [(0, "ah"), (0.7, "a")], breath=0.3, h_onset=0.05, shift=0.9, fry=0.35, tension=0.75, curve=lambda x: x**0.7)
    )
    inhale = fft_filter(noise(0.35), lo=900, hi=4500) * np.linspace(0.05, 0.6, int(0.35 * SR)) ** 2 * 0.5
    parts += [silence(0.06), inhale]
    return drive(human(parts, room=0.1) * 1.4, 1.3)


@sound
def ParentWake():
    # A dad jolted awake: snort, sharp gasp, "HUH?!", then "Wha--who's there?"
    snort = env(fft_filter(noise(0.12), lo=150, hi=900), a=0.01, r=0.04) * 0.8
    gasp = syllable(0.2, 180, 260, [(0, "ah")], breath=1.4, h_onset=0.18, tension=0.3) * 0.7
    huh = syllable(0.3, 150, 290, [(0, "uh")], breath=0.35, h_onset=0.06, tension=0.75, curve=lambda x: x**1.6)
    wha = syllable(0.2, 210, 180, [(0, "w"), (0.35, "ah")], breath=0.3)
    whos = syllable(0.17, 200, 190, [(0, "h"), (0.3, "oo")], breath=0.35, h_onset=0.06)
    there = syllable(0.36, 190, 280, [(0, "e"), (0.6, "uh")], breath=0.3, curve=lambda x: x**1.8)
    z = silence
    return human([snort, z(0.05), gasp, z(0.04), huh, z(0.3), wha, z(0.1), whos, z(0.02), there], room=0.15)


@sound
def CorgiWoof():
    # Two real-ish "ruff!" barks: noisy, chaotic, fast pitch drop, sharp attack.
    def bark(f0, dur):
        n = int(dur * SR)
        x = np.linspace(0, 1, n)
        f = f0 * (1.35 - 0.6 * x)
        buzz, flow = glottal(f, n, jitter=0.06, shimmer=0.35, tension=0.85)
        chaos = glottal(f * 0.5, n, jitter=0.1, shimmer=0.5)[0] * 0.45
        asp = fft_filter(noise(dur), lo=600, hi=8000)[:n] * (0.6 + flow)
        src = buzz + chaos + asp * 0.9
        out = formant_bank(src, [(0, "a"), (0.6, "u")], n, shift=1.45)
        e = np.minimum(1, x * 40) * np.exp(-x * 3.5)
        return out * e

    out = silence(0.6)
    place(out, bark(430, 0.15), 0.0)
    place(out, bark(470, 0.13), 0.21)
    return drive(reverb(out, 0.3, 0.1) * 2.0, 1.6)


@sound
def Gasp():
    # A sharp, surprised intake of breath with a little voiced "ah!" at the top.
    n = int(0.42 * SR)
    x = np.linspace(0, 1, n)
    air = fft_filter(noise(0.42), lo=700, hi=6000)[:n]
    air = formant_bank(air, [(0, "h"), (0.5, "ah")], n) * 2.5
    e = np.minimum(1, x * 9) * np.exp(-np.maximum(0, x - 0.55) * 6)
    voiced = syllable(0.14, 300, 380, [(0, "ah")], breath=0.9, tension=0.3) * 0.5
    out = air * e
    place(out, voiced, 0.22)
    return human([out], room=0.08)


@sound
def BreathStrain():
    # "Mmmmph!" Cheeks puffed, holding it in: a shaky, strained nasal hum.
    n = int(0.8 * SR)
    x = np.linspace(0, 1, n)
    f0 = 210 + 40 * x + 8 * np.sin(2 * np.pi * 7 * x * 0.8)
    buzz, flow = glottal(f0, n, jitter=0.03, shimmer=0.25, tension=0.95)
    hum = formant_bank(buzz, [(0, "m")], n)
    shake = 0.7 + 0.3 * np.sin(2 * np.pi * 11 * np.arange(n) / SR)
    leak = fft_filter(noise(0.8), lo=1500, hi=5000)[:n] * 0.04 * (x > 0.7)  # air leaking out
    return env(hum * shake + leak, a=0.06, r=0.12)


def beep_horn(f, dur, bend=1.06):
    """A bright, toy-car 'beep': two-tone square through a brassy filter."""
    n = int(dur * SR)
    x = np.linspace(0, 1, n)
    ff = f * (1 + (bend - 1) * np.minimum(1, x * 6))
    tone = osc(ff, shape="square") * 0.6 + osc(ff * 1.25, shape="square") * 0.45 + osc(ff * 2, shape="saw") * 0.15
    tone = fft_filter(tone, lo=250, hi=4200)
    return env(drive(tone * 1.5, 1.4), a=0.008, r=0.04)


@sound
def SleighHorn():
    # BEEP-BEEP! Cheery and loud: the sleigh is about to go.
    return cat(beep_horn(523, 0.2), silence(0.09), beep_horn(523, 0.34), silence(0.03))


@sound
def LastCall():
    # Two quicker, higher BEEP-BEEPs with a jingle on top: hurry!
    out = cat(beep_horn(659, 0.15, 1.08), silence(0.06), beep_horn(659, 0.26, 1.08), silence(0.05))
    place(out, jingle_hit(0.3) * 0.35, 0.21)
    return out


def shaker(dur=0.12, bright=1.0):
    """Sleigh bells as a soft shaker (filtered noise), no clangy partials."""
    n = int(dur * SR)
    x = np.linspace(0, 1, n)
    s = fft_filter(noise(dur), lo=5000 * bright, hi=11000)[:n]
    return s * np.minimum(1, x * 25) * np.exp(-x * 9) * 0.6


def glock(freq, dur):
    """Soft glockenspiel/celesta: harmonic, round, no metal clang."""
    t = t_axis(dur)
    tone = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * freq * 2 * t) * np.exp(-t * 9)
    return tone * np.exp(-t * 3.2) * env(len(t), a=0.003, r=0.02)


@sound
def FlightBells():
    # A happy flying loop: soft sleigh-bell shakes in a swinging rhythm and a
    # cheerful glockenspiel twinkle in C major (2 s, loops).
    d = 2.0
    out = silence(d + 1)
    for b in np.arange(0, d, 0.25):
        place(out, shaker(0.14) * (1.0 if (b * 4) % 2 == 0 else 0.55), b)
    for at, n in ((0.0, "C6"), (0.25, "E6"), (0.5, "G6"), (0.75, "E6"), (1.0, "A6"), (1.25, "G6"), (1.5, "E6"), (1.75, "D6")):
        place(out, glock(hz(n), 0.6) * 0.35, at)
    return loop_wrap(out, int(d * SR))


@sound
def Boing():
    # Bigger, brighter and louder spring.
    d = 0.75
    t = t_axis(d)
    f = 170 * (1 + 0.6 * t / d) * (1 + 0.4 * np.sin(2 * np.pi * 13 * t) * np.exp(-t * 3.5))
    tone = osc(f, shape="sine") + 0.5 * osc(f * 2, shape="tri") + 0.25 * osc(f * 3, shape="saw")
    return drive(env(tone, a=0.002, r=0.15) * np.exp(-t * 2.2) * 1.6, 1.5)


@sound
def KrampusComing():
    # Same goofy roar, with no low thud at the end: the bell hit moves to the
    # start and the tail fades out clean.
    d = 1.6
    f = cat(glide(90, 140, 0.4), glide(140, 75, 1.2))
    roar = voice(f, [(0, "a"), (0.5, "o"), (0.9, "u")], d, rough=0.6, breath=0.4)
    roar = drive(env(roar, a=0.08, r=0.5) * 4, 2.5)
    out = silence(2.0)
    place(out, mix(bell(440, 1.0, 1.0, 4), bell(466, 1.0, 1.0, 4)) * 0.3, 0)
    place(out, jingle_hit(0.4), 0)
    place(out, roar, 0.12)
    out = fft_filter(out, lo=140)
    out *= np.minimum(1, np.linspace(2.0, 0, len(out)) / 0.5)  # fade the last 0.5 s
    return reverb(out, 0.8, 0.18)[: len(out)]


@sound
def TinDogWhirr():
    # Clockwork that slows and fades instead of stopping dead.
    d = 1.3
    out = silence(d)
    at, gap = 0.0, 1 / 18
    while at < d - 0.05:
        g = 0.6 * (1 - max(0, at - 0.7) / 0.6)
        place(out, mix(click(0.008, 3000, g), decay(osc(2400, 0.02), 200) * 0.3 * g), at)
        at += gap
        if at > 0.7:
            gap *= 1.07
    whirr = osc(glide(300, 230, d), shape="saw") * 0.08 * np.linspace(1, 0, int(d * SR)) ** 0.7
    return mix(out, fft_filter(whirr, hi=2000))


@sound
def NoiseWarn():
    # Three quick warning beeps.
    b = env(osc(1175, 0.09, shape="square") * 0.5 + osc(1175, 0.09) * 0.5, a=0.004, r=0.02)
    b = fft_filter(b, hi=4000)
    return cat(b, silence(0.07), b, silence(0.07), b, silence(0.03))


@sound
def Wiggle():
    # A quick wriggle-shuffle: two cloth swishes in the sack.
    def swish(dur, lo, hi):
        n = int(dur * SR)
        x = np.linspace(0, 1, n)
        s = lowpass_sweep(fft_filter(noise(dur), lo=lo)[:n], hi * 0.4, hi)
        return s * np.sin(np.pi * x) ** 1.5
    out = silence(0.3)
    place(out, swish(0.11, 900, 6000), 0)
    place(out, swish(0.13, 700, 5000) * 0.8, 0.12)
    return out


@sound
def DoorOpen():
    # Friendly: handle click-clack, a soft swing of air, a tiny wooden tap.
    out = silence(0.6)
    place(out, click(0.012, 1500, 0.8), 0.0)
    place(out, click(0.01, 2500, 0.5), 0.05)
    sw = lowpass_sweep(noise(0.35), 300, 1800) * np.sin(np.linspace(0, np.pi, int(0.35 * SR))) * 0.35
    place(out, sw, 0.08)
    place(out, thump(220, 140, 0.08, 0.3) * 0.4, 0.42)
    return out


@sound
def HideOut():
    # Wardrobe pops open and you hop out: latch, swish, a light landing.
    out = silence(0.6)
    place(out, click(0.012, 1800, 0.8), 0.0)
    place(out, lowpass_sweep(noise(0.25), 500, 3000) * np.sin(np.linspace(0, np.pi, int(0.25 * SR))) * 0.4, 0.04)
    place(out, thump(160, 90, 0.15, 0.4) * 0.8, 0.32)
    place(out, decay(fft_filter(noise(0.1), hi=1500), 30) * 0.3, 0.32)
    return out


KIT2 = dict(KIT)
KIT2["shaker"] = lambda: shaker(0.1) * 0.8
KIT2["jingle"] = KIT2["shaker"]  # no metal bells in the drum kit


@sound
def HurryMusic():
    bpm, beats = 168, 32  # galloping chase in D major
    chords = ["D", "D", "G", "A", "D", "B", "G", "A"]
    roots = {"D": "D2", "G": "G2", "A": "A2", "B": "B1"}
    bass = []
    for bar, c in enumerate(chords):
        for b in range(4):
            bass.append((bar * 4 + b, 0.45, roots[c] if b % 2 == 0 else roots[c][:-1] + "3", 0.8))
    mel_notes = ["F#4", "A4", "D5", "A4", "B4", "G4", "E4", "A4", "F#4", "A4", "D5", "F#5", "D5", "B4", "C#5", "E5"]
    mel = [(k * 2, 1.6, n, 0.5) for k, n in enumerate(mel_notes)]
    sparkle = [(k * 2 + 1, 0.5, n[:-1] + str(int(n[-1]) + 1), 0.25) for k, n in enumerate(mel_notes)]
    pat = []
    for b in range(beats):
        pat.append((b, "kick" if b % 2 == 0 else "snare"))
        pat.append((b + 0.5, "hat"))
        pat.append((b, "shaker"))
        pat.append((b + 0.5, "shaker"))
    tune = music([(bass, bassoon, 0.6), (mel, brass, 0.45), (sparkle, glock, 0.5)], bpm, beats)
    return tune + drums(pat, bpm, beats, KIT2) * 0.7


@sound
def LobbyMusic():
    bpm, beats = 120, 32  # cheerful own tune in F major, soft glockenspiel lead
    chords = [("F3", "A3", "C4"), ("Bb2", "D3", "F3"), ("C3", "E3", "G3"), ("F3", "A3", "C4")] * 2
    pad = []
    for bar, ch in enumerate(chords):
        for n in ch:
            pad.append((bar * 4, 3.8, n, 0.25))
    bass = [(bar * 4 + b, 0.9, ch[0][:-1] + "2", 0.6) for bar, ch in enumerate(chords) for b in (0, 2)]
    tones = ["C5", "A4", "F4", "A4", "D5", "Bb4", "F4", "Bb4", "E5", "C5", "G4", "C5", "F5", "C5", "A4", "F4"]
    mel = []
    for k, n in enumerate(tones):
        mel.append((k * 2, 0.9, n, 0.55))
        mel.append((k * 2 + 1, 0.5, n, 0.3))
    pat = [(b, "shaker") for b in range(beats)] + [(b + 0.5, "shaker") for b in range(beats)]
    pat += [(b, "kick") for b in range(0, beats, 2)] + [(b + 1, "snare") for b in range(0, beats, 2)]
    tune = music(
        [(pad, lambda f, d: env(osc(f, d, "tri"), a=0.2, r=0.5), 0.6), (bass, ks_fast, 0.7), (mel, glock, 0.6)], bpm, beats
    )
    return tune + drums(pat, bpm, beats, KIT2) * 0.45


@sound
def KrampusMusic():
    bpm, beats = 164, 32  # faster: spooky-silly bassoon oompah in C minor
    roots = ["C2", "G1", "Ab1", "G1"]
    bass = []
    for bar in range(8):
        r = roots[bar % 4]
        for b in range(4):
            bass.append((bar * 4 + b, 0.4, r if b % 2 == 0 else r[:-1] + str(int(r[-1]) + 1), 0.8))
    mel_notes = ["C4", "Eb4", "G4", "F#4", "G4", "Ab4", "G4", "Eb4", "C4", "D4", "Eb4", "B3", "C4", "G3", "C4", "C4"]
    mel = [(k * 2, 1.5, n, 0.55) for k, n in enumerate(mel_notes)]
    pat = [(b, "tick" if b % 2 == 0 else "tock") for b in range(beats)]
    pat += [(b, "kick") for b in range(beats)] + [(b + 1, "snare") for b in range(0, beats, 2)]
    pat += [(b + 0.5, "hat") for b in range(beats)]
    tune = music([(bass, bassoon, 0.7), (mel, lambda f, d: bassoon(f * 2, d), 0.35)], bpm, beats)
    return tune + drums(pat, bpm, beats, KIT2) * 0.6


# ---------------------------------------------------------------------------
# Cutscenes (PR #10 brief, 4 Nov). One version each; music fades at the end
# so a skip can cut it anywhere. Times match src/shared/Cutscenes.luau.
# ---------------------------------------------------------------------------


@sound
def CutsceneSneeze():
    ah = syllable(0.32, 220, 330, [(0, "ah")], breath=0.5, h_onset=0.1, tension=0.4, curve=lambda x: x**1.5)
    choo = syllable(0.16, 380, 250, [(0, "oo")], breath=1.2, h_onset=0.03, tension=0.9)
    burst = env(fft_filter(noise(0.12), lo=1500, hi=9000), a=0.003, r=0.08)
    return human([ah, silence(0.05), mix(burst, choo)], room=0.12)


@sound
def CutsceneThump():
    return mix(thump(85, 38, 0.45, 0.25) * 1.2, decay(fft_filter(noise(0.4), hi=1200), 10) * 0.4, place(silence(0.5), jingle_hit(0.3) * 0.4, 0.02))


@sound
def CutsceneBells():
    # 2.8 s: distant bells building closer, with a heartbeat under them.
    d = 2.8
    out = silence(d + 0.5)
    for k, at in enumerate(np.arange(0, d - 0.1, 0.28)):
        g = 0.25 + 0.75 * (at / d) ** 1.5
        place(out, jingle_hit(0.3) * g, at)
    for at in np.arange(0.2, d, 0.75):
        place(out, KrampusHeartbeat() * 0.8, at)
    near = np.linspace(0, 1, len(out))
    far = fft_filter(out, hi=1800)
    out = far * (1 - near) + out * near
    return reverb(out, 1.2, 0.3)[: int(d * SR)]


@sound
def CutsceneClonk():
    return mix(bell(392, 0.8, 1.4, 5) * 0.7, thump(140, 70, 0.2, 0.6), click(0.02, 900, 0.7))


@sound
def CutsceneRoar():
    # Goofy, not scary: a big "BLEHHH!" with a wobble.
    n = int(1.1 * SR)
    x = np.linspace(0, 1, n)
    f0 = 110 + 40 * np.sin(np.pi * x) + 12 * np.sin(2 * np.pi * 9 * x * 1.1)
    buzz, flow = glottal(f0, n, jitter=0.03, shimmer=0.2, tension=0.8)
    sub = glottal(f0 * 0.5, n, jitter=0.05)[0] * 0.4
    asp = fft_filter(noise(1.1), lo=300, hi=6000)[:n] * (0.5 + flow) * 0.5
    out = formant_bank(buzz + sub + asp, [(0, "e"), (0.4, "ah"), (0.85, "uh")], n, shift=0.85)
    return reverb(drive(env(out, a=0.04, r=0.25) * 2, 1.6), 0.8, 0.2)


@sound
def CutsceneStrain():
    # "Nnnnngh!" heaving the loot sack: a pressed, rising grunt.
    n = int(0.9 * SR)
    x = np.linspace(0, 1, n)
    f0 = 150 + 70 * x**1.4
    buzz, flow = glottal(f0, n, jitter=0.03, shimmer=0.3, tension=0.95)
    out = formant_bank(buzz, [(0, "m"), (0.3, "uh")], n)
    return env(out * (0.7 + 0.3 * np.sin(2 * np.pi * 8 * np.arange(n) / SR)), a=0.05, r=0.15)


@sound
def CutsceneFlump():
    # Krampus belly-flops into the snow: a soft heavy FLUMP and a puff.
    return mix(thump(70, 32, 0.6, 0.15) * 1.3, decay(fft_filter(noise(0.7), lo=200, hi=2500), 6) * 0.6)


@sound
def CutsceneStamp():
    # "LOOT x2" stamped on screen: a punchy stamp plus a bright ding.
    return mix(thump(180, 90, 0.18, 0.9), click(0.02, 1200, 0.8), place(silence(0.9), bell(1568, 0.8, 0.5, 4) * 0.6, 0.04))


@sound
def CutsceneYoink():
    # A quick rising slide-whistle "yoink!"
    return slide_whistle(500, 1900, 0.28)


@sound
def CutsceneBonk():
    return mix(bell(880, 0.5, 1.2, 8) * 0.5, thump(260, 160, 0.12, 0.8), osc(glide(700, 500, 0.15), shape="tri") * np.exp(-t_axis(0.15) * 20) * 0.4)


@sound
def CutsceneHonk():
    # The sleigh leaving without you: the BEEP-BEEP, a little further away.
    return reverb(fft_filter(cat(beep_horn(523, 0.18), silence(0.07), beep_horn(523, 0.3)), hi=3000), 0.6, 0.3)


@sound
def CutsceneRaspberry():
    # A cheeky "pfffbbbt!" from the reindeer.
    n = int(0.7 * SR)
    x = np.linspace(0, 1, n)
    f0 = 95 + 25 * np.sin(2 * np.pi * 3 * x)
    buzz = glottal(f0, n, jitter=0.12, shimmer=0.6, tension=1.0)[0]
    flap = 0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 34 * np.arange(n) / SR))
    out = formant_bank(buzz * flap + fft_filter(noise(0.7), lo=500)[:n] * 0.3, [(0, "u")], n, shift=1.2)
    return env(out, a=0.01, r=0.12)


def fade_tail(sig, seconds=0.25):
    n = int(seconds * SR)
    sig = sig.copy()
    sig[-n:] *= np.linspace(1, 0, n)
    return sig


def score(length, parts, bpm):
    """A one-shot cue: like music() but cut to `length` seconds, faded."""
    beats = length * bpm / 60
    beat = 60 / bpm
    out = silence(length + 2)
    for notes, inst, gain in parts:
        for start, dur, note, g in notes:
            f = hz(note) if isinstance(note, str) else note
            place(out, inst(f, dur * beat) * g * gain, start * beat)
    return fade_tail(out[: int(length * SR)], 0.2)


@sound
def CutsceneMusicTakeoff():
    # 5 s cheeky heist overture: pizzicato, bells, a swell at 2.4, button at 4.6.
    bpm = 120  # 1 beat = 0.5 s; 4.6 s = beat 9.2
    pizz = [(b * 0.5, 0.45, n, 0.8) for b, n in enumerate(["E3", "G3", "B3", "G3", "C4", "B3", "A3", "B3"])]
    lead = [(4.8, 0.5, "B4", 0.6), (5.3, 0.5, "C5", 0.6), (5.8, 0.5, "D5", 0.7), (6.3, 0.5, "E5", 0.8), (6.8, 2, "G5", 0.7)]
    button = [(9.2, 0.6, "E3", 1.0), (9.2, 0.6, "E4", 0.8), (9.2, 0.6, "B4", 0.6)]
    out = score(5.0, [(pizz, ks_fast, 0.9), (lead, brass, 0.4), (button, brass, 0.6)], bpm)
    swell = lowpass_sweep(noise(2.2), 300, 6000) * np.linspace(0, 1, int(2.2 * SR)) ** 2 * 0.25
    place(out, swell, 2.4)
    for at in np.arange(0, 4.5, 0.25):
        place(out, shaker(0.1) * 0.5, at)
    place(out, jingle_hit(0.4) * 0.6, 4.6)
    return out


@sound
def CutsceneMusicKrampus():
    # 4 s comic-spooky: tuba/bassoon creep in C minor, brass stab at 2.8.
    bpm = 120
    creep = [(0, 0.9, "C2", 0.8), (1, 0.9, "D2", 0.8), (2, 0.9, "Eb2", 0.8), (3, 0.9, "F#2", 0.8), (4, 1.0, "G2", 0.9)]
    tick = [(b * 0.5, 0.1, "G4", 0.25) for b in range(11)]
    stab = [(5.6, 1.6, n, 0.7) for n in ("C3", "Eb3", "Gb3", "C4")]
    return score(4.0, [(creep, bassoon, 0.9), (tick, marimba, 0.6), (stab, brass, 0.55)], bpm)


@sound
def CutsceneMusicGetaway():
    # 4 s triumphant caper: strain build, fanfare at 1.3, big hit at 2.8.
    bpm = 120
    build = [(0, 2.6, "G2", 0.7), (0, 2.6, "D3", 0.5)]
    fan = [(2.6, 0.3, "C4", 0.6), (2.9, 0.3, "E4", 0.6), (3.2, 0.3, "G4", 0.6), (3.5, 1.6, "C5", 0.7)]
    hit = [(5.6, 1.6, n, 0.7) for n in ("C3", "G3", "C4", "E4", "G4")]
    out = score(4.0, [(build, bassoon, 0.6), (fan, brass, 0.5), (hit, brass, 0.6)], bpm)
    place(out, lowpass_sweep(noise(1.2), 200, 4000) * np.linspace(0, 1, int(1.2 * SR)) ** 2 * 0.2, 0.1)
    place(out, jingle_hit(0.4) * 0.6, 2.8)
    place(out, thump(110, 50, 0.3, 0.3) * 0.7, 2.8)
    return out


@sound
def CutsceneMusicSnatched():
    # 2 s slide-whistle sting, up then plunging down, with a timpani tap.
    out = silence(2.0)
    place(out, slide_whistle(400, 1500, 0.35) * 0.8, 0.05)
    place(out, slide_whistle(1500, 300, 0.7) * 0.8, 0.45)
    place(out, thump(90, 60, 0.4, 0.2) * 0.7, 1.2)
    return fade_tail(out, 0.2)


@sound
def CutsceneMusicLeftBehind():
    # 2 s quick sad-trombone "wah wah wah waaah".
    parts = []
    for n, d in (("D4", 0.28), ("C#4", 0.28), ("C4", 0.28), ("B3", 0.95)):
        t = t_axis(d)
        vib = 0.03 * np.sin(2 * np.pi * 6 * t) * np.clip((t - 0.25) / 0.2, 0, 1) if d > 0.5 else 0 * t
        tone = osc(hz(n) * (1 + vib), shape="saw")
        parts += [env(lowpass_sweep(tone, np.geomspace(350, 1800, len(t)), None), a=0.02, r=0.1), silence(0.04)]
    return fade_tail(cat(*parts)[: int(2.0 * SR)], 0.2)


# ---------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------

LOOPS = {"FlightBells", "KrampusBells", "KrampusHeartbeat", "ParentSnore", "PolisherHum", "NightAmbience", "SneakMusic", "HurryMusic", "KrampusMusic", "LobbyMusic"}


def loudest_rms(sig, window=0.3):
    """RMS of the loudest `window` seconds: a rough stand-in for loudness."""
    n = max(1, int(window * SR))
    if len(sig) <= n:
        return float(np.sqrt(np.mean(sig**2)))
    power = np.convolve(sig**2, np.ones(n) / n, mode="valid")
    return float(np.sqrt(np.max(power)))


def finish(key, sig):
    """Even loudness across keys (Sounds.luau volumes do the per-key mix),
    with a soft limiter so nothing clips on phone speakers."""
    sig = np.nan_to_num(np.asarray(sig, dtype=float))
    sig = sig - np.mean(sig)
    sig = fft_filter(sig, lo=35, hi=11000)  # no subsonic rumble, no harsh fizz
    if key not in LOOPS:
        sig = cat(sig, silence(0.02))
        fade = min(len(sig) // 4, int(0.01 * SR))
        sig[-fade:] *= np.linspace(1, 0, fade)
    target = 0.12 if key in LOOPS else 0.2  # about -20 / -14 dBFS RMS
    sig = sig * (target / (loudest_rms(sig) or 1.0))
    ceiling = 0.68  # leaves room for encoder overshoot on clicks
    over = np.abs(sig) > ceiling * 0.7
    if over.any():  # soft-knee limiter above 70% of the ceiling
        knee = ceiling * 0.7
        mag = np.abs(sig)
        mag = np.where(over, knee + (ceiling - knee) * np.tanh((mag - knee) / (ceiling - knee)), mag)
        sig = np.sign(sig) * mag
    return sig


def write_wav(path, sig):
    data = (np.clip(sig, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "audio"
    keys = sys.argv[2:] or list(S)
    os.makedirs(out_dir, exist_ok=True)
    for key in keys:
        sig = finish(key, S[key]())
        wav = os.path.join(out_dir, key + ".wav")
        ogg = os.path.join(out_dir, key + ".ogg")
        write_wav(wav, sig)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
        os.remove(wav)
        print(f"{key:18s} {len(sig) / SR:5.2f}s")


if __name__ == "__main__":
    main()
