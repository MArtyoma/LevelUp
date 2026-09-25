#!/usr/bin/env python3
"""Режет запись ходьбы на отдельные шаги — для звука шагов в игре.

Зачем. Stable Audio на просьбу «один шаг» отдаёт щелчок на 0,04 с или шаг с хвостом
следующего. А на «шаги по плитке, ровный темп» — чистую серию, где удары отлично
видны. Поэтому шаги генерируются серией и режутся здесь:

  python3 tools/audio/gen_audio.py steps_tile "footsteps walking slowly on hard ceramic tile floor \\
      in an office corridor, clear heel taps, even pace, dry, close microphone" --seconds 4 --count 3 --seed 41
  python3 tools/audio/slice_steps.py audio_out/steps_tile/0*.wav --out audio_out/cut_tile --dur 0.13

В audio_out/cut_tile/ — NN.wav по одному шагу и sheet.png со спектрограммами.
Смотреть на sheet.png: у хорошего шага один удар в начале; вторая вертикальная
полоса ближе к концу — туда попал следующий шаг, такой брать не надо (или --dur короче).
Выбранные — в assets/sfx/step_<поверхность>_N_placeholder.wav.

Как находится шаг: огибающая «разности соседних сэмплов» (грубый фильтр высоких частот:
удар каблука, а не гул), и шаг — где она прыгает на 9 dB за 12 мс и на 12 dB выше медианы.
Дальше: 4 мс до удара, --dur после, затухание на последних 40 %, пик -3 dBFS.
Только стандартная библиотека Python (+ Pillow и ffmpeg для sheet.png, если есть).
"""
import argparse
import array
import math
import statistics
import sys
import wave
from pathlib import Path

GAME = Path(__file__).resolve().parents[2]
WINDOW_MS = 4


def load(path):
    with wave.open(str(path)) as w:
        if w.getsampwidth() != 2 or w.getnchannels() != 1:
            sys.exit(f"{path}: нужен WAV 16 бит моно (такой отдаёт gen_audio.py)")
        return w.getframerate(), array.array("h", w.readframes(w.getnframes()))


def onsets(samples, rate):
    n = int(rate * WINDOW_MS / 1000)
    env = []
    for i in range(0, len(samples) - n, n):
        power = sum((samples[j] - samples[j - 1]) ** 2 for j in range(i + 1, i + n)) / n
        env.append(10 * math.log10(power + 1))
    median = statistics.median(env)
    found, last = [], -10 ** 9
    for i in range(3, len(env)):
        if env[i] > median + 12 and env[i] - min(env[i - 3:i]) > 9 and i - last > 180 // WINDOW_MS:
            found.append(i * n)
            last = i
    return found


def cut(samples, rate, start, dur, pre=0.004):
    begin = max(0, start - int(pre * rate))
    seg = list(samples[begin:begin + int(dur * rate)])
    if len(seg) < int(dur * rate):
        return None, -99.0
    fade = int(0.4 * dur * rate)
    for k in range(fade):
        seg[-1 - k] = int(seg[-1 - k] * k / fade)
    lead = int(pre * rate)
    for k in range(lead):
        seg[k] = int(seg[k] * k / lead)
    peak = max(abs(x) for x in seg) or 1
    gain = 32767 * 10 ** (-3 / 20) / peak
    return array.array("h", [int(x * gain) for x in seg]), 20 * math.log10(peak / 32768)


def sheet(files, out):
    try:
        sys.path.insert(0, str(Path(__file__).parent))
        import gen_audio
        from PIL import Image
    except ImportError:
        return
    tiles = []
    for f in files:
        png = f.with_suffix(".png")
        gen_audio.spectrogram(f, png, f.name)
        tiles.append(Image.open(png).resize((320, 80)))
        png.unlink()
    cols = 4
    img = Image.new("RGB", (320 * cols, 80 * ((len(tiles) + cols - 1) // cols)))
    for i, t in enumerate(tiles):
        img.paste(t, ((i % cols) * 320, (i // cols) * 80))
    img.save(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+", type=Path, help="записи ходьбы (WAV из gen_audio.py)")
    ap.add_argument("--out", type=Path, required=True, help="куда класть шаги (относительно game/)")
    ap.add_argument("--dur", type=float, default=0.15, help="длина шага, с (по умолчанию 0.15)")
    ap.add_argument("--min-peak", type=float, default=-30.0,
                    help="тише этого (dBFS, до нормализации) — не шаг, а шорох")
    a = ap.parse_args()

    out = a.out if a.out.is_absolute() else GAME / a.out
    out.mkdir(parents=True, exist_ok=True)
    (out.parent / ".gdignore").touch()
    written = []
    for f in a.files:
        rate, samples = load(f)
        for start in onsets(samples, rate):
            seg, peak = cut(samples, rate, start, a.dur)
            if seg is None or peak < a.min_peak:
                continue
            path = out / f"{len(written):02d}.wav"
            with wave.open(str(path), "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(rate)
                w.writeframes(seg.tobytes())
            print(f"{path.name}  из {f.parent.name}/{f.name} на {start / rate:.2f} с")
            written.append(path)
    if written:
        sheet(written, out / "sheet.png")
    print(f"шагов: {len(written)} -> {out}")


if __name__ == "__main__":
    main()
