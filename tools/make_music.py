# Generates the two original music loops (battle + menu) used by the game. Output: audio/*.ogg
import numpy as np, subprocess, wave
SR = 32000
def note(m): return 440.0 * 2 ** ((m - 69) / 12)
def env(n, a=0.01, r=0.2):
    e = np.ones(n); na = max(1, int(a * SR)); nr = max(1, int(r * SR))
    e[:na] = np.linspace(0, 1, na); e[-nr:] *= np.linspace(1, 0, nr); return e
def saw(f, n): t = np.arange(n) / SR; return 2 * ((t * f) % 1.0) - 1
def sq(f, n): return np.sign(np.sin(2 * np.pi * f * np.arange(n) / SR))
def lp(x, k=0.15):
    y = np.zeros_like(x); acc = 0.0
    for i in range(len(x)): acc += k * (x[i] - acc); y[i] = acc
    return y
def write(name, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.85
    pcm = (x * 32767).astype(np.int16)
    with wave.open(f'/tmp/{name}.wav', 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', f'/tmp/{name}.wav', '-c:a', 'libvorbis', '-q:a', '2', f'{name}.ogg'], check=True)

# ---- battle: 124 bpm, D minor, 8 bars
bpm = 124; beat = 60 / bpm; bars = 8; N = int(bars * 4 * beat * SR)
out = np.zeros(N)
prog = [(50, [62, 65, 69]), (46, [58, 62, 65]), (48, [60, 64, 67]), (45, [57, 61, 64])]  # Dm Bb C A
for bar in range(bars):
    root, chord = prog[bar % 4]
    b0 = int(bar * 4 * beat * SR)
    # bass ostinato 8ths
    for i in range(8):
        n = int(beat / 2 * SR); s = b0 + i * n
        m = root - 12 + (12 if i in (3, 6) else 0)
        out[s:s + n] += 0.35 * lp(saw(note(m), n), 0.08) * env(n, 0.005, 0.08)
    # brass-ish stab pad
    n = int(4 * beat * SR)
    pad = sum(lp(saw(note(m) * d, n), 0.04) for m in chord for d in (1.0, 1.003))
    out[b0:b0 + n] += 0.12 * pad * env(n, 0.3, 0.6)
    # lead motif every other bar
    if bar % 2 == 1:
        motif = [chord[2] + 12, chord[1] + 12, chord[2] + 12, chord[0] + 12 + 2]
        for i, m in enumerate(motif):
            ln = int(beat * SR); s = b0 + i * ln
            out[s:s + ln] += 0.1 * lp(sq(note(m), ln), 0.2) * env(ln, 0.01, 0.3)
    # drums: kick on 1,3; snare on 2,4; hats 8ths
    for i in range(8):
        s = b0 + int(i * beat / 2 * SR)
        if i % 4 == 0:
            n = int(0.25 * SR); t = np.arange(n) / SR
            out[s:s + n] += 0.6 * np.sin(2 * np.pi * (50 + 90 * np.exp(-t * 30)) * t) * np.exp(-t * 12)
        if i % 4 == 2:
            n = int(0.18 * SR); t = np.arange(n) / SR
            out[s:s + n] += 0.3 * np.random.uniform(-1, 1, n) * np.exp(-t * 22) + 0.15 * np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25)
        n = int(0.04 * SR); t = np.arange(n) / SR
        out[s:s + n] += 0.06 * np.random.uniform(-1, 1, n) * np.exp(-t * 90)
write('battle', out)

# ---- menu: slow pads, 70 bpm, 8 bars
bpm = 70; beat = 60 / bpm; N = int(8 * 4 * beat * SR); out = np.zeros(N)
for bar in range(8):
    root, chord = prog[(bar // 2) % 4]
    b0 = int(bar * 4 * beat * SR); n = int(4 * beat * SR)
    out[b0:b0 + n] += 0.25 * lp(saw(note(root - 12), n), 0.03) * env(n, 0.5, 0.8)
    out[b0:b0 + n] += 0.12 * sum(lp(saw(note(m) * d, n), 0.025) for m in chord for d in (0.997, 1.004)) * env(n, 1.0, 1.2)
    for i, m in enumerate([chord[2] + 12, chord[1] + 12] if bar % 2 == 0 else [chord[0] + 12, chord[2] + 12]):
        ln = int(2 * beat * SR); s = b0 + i * ln
        out[s:s + ln] += 0.07 * np.sin(2 * np.pi * note(m) * np.arange(ln) / SR) * env(ln, 0.1, 1.0)
write('menu', out)
