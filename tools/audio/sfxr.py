#!/usr/bin/env python3
"""Процедурные ретро-звуки для LevelUp — алгоритм sfxr (DrPetter, 2007), без нейросетей.

Зачем он, если есть Stable Audio. Короткие «игровые» звуки — писк текста в диалоге,
клик меню, «квест выполнен», подобранный предмет — sfxr делает лучше нейросети:
мгновенно, без тишины в начале, в стилистике пиксель-арта, и один и тот же
параметр-файл всегда даёт один и тот же звук. Нейросеть — для «настоящих» звуков
(шаги по ковролину, кофемашина, гул офиса): см. tools/audio/gen_audio.py.

  # 5 вариантов «подобрал предмет» -> audio_out/pickup/pickup_00.wav ...
  python3 tools/audio/sfxr.py pickup --count 5

  # писк реплики NPC: у каждого персонажа своя высота голоса
  python3 tools/audio/sfxr.py talk --name talk_hr --pitch 0.55

  # понравился вариант 3 — у каждого .wav рядом лежит .json с параметрами;
  # поправить руками (например, env_decay) и пересобрать ровно его:
  python3 tools/audio/sfxr.py --params audio_out/pickup/pickup_03.json --name coin

Пресеты: см. PRESETS ниже (--list). Результат: WAV 44.1 кГц, 16 бит, моно —
для Godot короткие звуки лучше именно в WAV (играются без задержки на декодирование).
Только стандартная библиотека Python.
"""

import argparse
import json
import math
import random
import struct
import sys
import wave
from pathlib import Path

RATE = 44100
GAME = Path(__file__).resolve().parents[2]

SQUARE, SAW, SINE, NOISE = 0, 1, 2, 3

# Параметры sfxr. Все в диапазоне 0..1 (кроме помеченных -1..1), как в оригинале,
# поэтому .json можно править руками, сверяясь с любым sfxr/jsfxr.
DEFAULTS = {
    "wave_type": SQUARE,
    "base_freq": 0.3, "freq_limit": 0.0, "freq_ramp": 0.0, "freq_dramp": 0.0,  # ramp, dramp: -1..1
    "duty": 0.0, "duty_ramp": 0.0,                                            # duty_ramp: -1..1
    "vib_strength": 0.0, "vib_speed": 0.0,
    "env_attack": 0.0, "env_sustain": 0.3, "env_punch": 0.0, "env_decay": 0.4,
    "lpf_freq": 1.0, "lpf_ramp": 0.0, "lpf_resonance": 0.0,                   # lpf_ramp: -1..1
    "hpf_freq": 0.0, "hpf_ramp": 0.0,                                         # hpf_ramp: -1..1
    "pha_offset": 0.0, "pha_ramp": 0.0,                                       # оба -1..1
    "repeat_speed": 0.0,
    "arp_speed": 0.0, "arp_mod": 0.0,                                         # arp_mod: -1..1
    "volume": 0.5,
}


def synth(p, rng=None):
    """Параметры -> список сэмплов float -1..1. Прямой перенос синтезатора sfxr."""
    rng = rng or random.Random(0)
    p = {**DEFAULTS, **p}
    st = {}

    def reset(restart):
        st["fperiod"] = 100.0 / (p["base_freq"] ** 2 + 0.001)
        st["fmaxperiod"] = 100.0 / (p["freq_limit"] ** 2 + 0.001)
        st["fslide"] = 1.0 - p["freq_ramp"] ** 3 * 0.01
        st["fdslide"] = -p["freq_dramp"] ** 3 * 0.000001
        st["square_duty"] = 0.5 - p["duty"] * 0.5
        st["square_slide"] = -p["duty_ramp"] * 0.00005
        am = p["arp_mod"]
        st["arp_mod"] = 1.0 - am * am * 0.9 if am >= 0 else 1.0 + am * am * 10.0
        st["arp_time"] = 0
        st["arp_limit"] = 0 if p["arp_speed"] == 1.0 else int((1.0 - p["arp_speed"]) ** 2 * 20000 + 32)
        if restart:
            return
        st["phase"] = 0
        st["fltp"] = st["fltdp"] = st["fltphp"] = 0.0
        st["fltw"] = p["lpf_freq"] ** 3 * 0.1
        st["fltw_d"] = 1.0 + p["lpf_ramp"] * 0.0001
        st["fltdmp"] = min(0.8, 5.0 / (1.0 + p["lpf_resonance"] ** 2 * 20.0) * (0.01 + st["fltw"]))
        st["flthp"] = p["hpf_freq"] ** 2 * 0.1
        st["flthp_d"] = 1.0 + p["hpf_ramp"] * 0.0003
        st["vib_phase"] = 0.0
        st["vib_speed"] = p["vib_speed"] ** 2 * 0.01
        st["vib_amp"] = p["vib_strength"] * 0.5
        st["env_vol"] = 0.0
        st["env_stage"] = 0
        st["env_time"] = 0
        st["env_length"] = [int(p["env_attack"] ** 2 * 100000), int(p["env_sustain"] ** 2 * 100000),
                            int(p["env_decay"] ** 2 * 100000)]
        st["fphase"] = math.copysign(p["pha_offset"] ** 2 * 1020.0, p["pha_offset"])
        st["fdphase"] = math.copysign(p["pha_ramp"] ** 2 * 1.0, p["pha_ramp"])
        st["iphase"] = abs(int(st["fphase"]))
        st["ipp"] = 0
        st["phaser"] = [0.0] * 1024
        st["noise"] = [rng.uniform(-1, 1) for _ in range(32)]
        st["rep_time"] = 0
        st["rep_limit"] = 0 if p["repeat_speed"] == 0 else int((1.0 - p["repeat_speed"]) ** 2 * 20000 + 32)

    reset(False)
    out = []
    wave_type = int(p["wave_type"])
    max_len = RATE * 6                                  # предохранитель от «бесконечных» параметров
    while len(out) < max_len:
        st["rep_time"] += 1
        if st["rep_limit"] and st["rep_time"] >= st["rep_limit"]:
            st["rep_time"] = 0
            reset(True)
        st["arp_time"] += 1
        if st["arp_limit"] and st["arp_time"] >= st["arp_limit"]:
            st["arp_limit"] = 0
            st["fperiod"] *= st["arp_mod"]
        st["fslide"] += st["fdslide"]
        st["fperiod"] *= st["fslide"]
        if st["fperiod"] > st["fmaxperiod"]:
            st["fperiod"] = st["fmaxperiod"]
            if p["freq_limit"] > 0:
                break
        rfperiod = st["fperiod"]
        if st["vib_amp"] > 0:
            st["vib_phase"] += st["vib_speed"]
            rfperiod = st["fperiod"] * (1.0 + math.sin(st["vib_phase"]) * st["vib_amp"])
        period = max(8, int(rfperiod))
        st["square_duty"] = min(0.5, max(0.0, st["square_duty"] + st["square_slide"]))

        st["env_time"] += 1
        if st["env_time"] > st["env_length"][st["env_stage"]]:
            st["env_time"] = 0
            st["env_stage"] += 1
            while st["env_stage"] < 3 and st["env_length"][st["env_stage"]] == 0:
                st["env_stage"] += 1
            if st["env_stage"] >= 3:
                break
        L, t = st["env_length"][st["env_stage"]], st["env_time"]
        if st["env_stage"] == 0:
            st["env_vol"] = t / L
        elif st["env_stage"] == 1:
            st["env_vol"] = 1.0 + (1.0 - t / L) * 2.0 * p["env_punch"]
        else:
            st["env_vol"] = 1.0 - t / L

        st["fphase"] += st["fdphase"]
        st["iphase"] = min(1023, abs(int(st["fphase"])))
        if st["flthp_d"] != 0:
            st["flthp"] = min(0.1, max(0.00001, st["flthp"] * st["flthp_d"]))

        ssample = 0.0
        for _ in range(8):                               # 8x передискретизация, как в оригинале
            st["phase"] += 1
            if st["phase"] >= period:
                st["phase"] %= period
                if wave_type == NOISE:
                    st["noise"] = [rng.uniform(-1, 1) for _ in range(32)]
            fp = st["phase"] / period
            if wave_type == SQUARE:
                s = 0.5 if fp < st["square_duty"] else -0.5
            elif wave_type == SAW:
                s = 1.0 - fp * 2.0
            elif wave_type == SINE:
                s = math.sin(fp * 2.0 * math.pi)
            else:
                s = st["noise"][st["phase"] * 32 // period]
            pp = st["fltp"]
            st["fltw"] = min(0.1, max(0.0, st["fltw"] * st["fltw_d"]))
            if p["lpf_freq"] != 1.0:
                st["fltdp"] += (s - st["fltp"]) * st["fltw"]
                st["fltdp"] -= st["fltdp"] * st["fltdmp"]
            else:
                st["fltp"] = s
                st["fltdp"] = 0.0
            st["fltp"] += st["fltdp"]
            st["fltphp"] += st["fltp"] - pp
            st["fltphp"] -= st["fltphp"] * st["flthp"]
            s = st["fltphp"]
            ph = st["phaser"]
            ph[st["ipp"] & 1023] = s
            s += ph[(st["ipp"] - st["iphase"] + 1024) & 1023]
            st["ipp"] = (st["ipp"] + 1) & 1023
            ssample += s * st["env_vol"]
        ssample = ssample / 8 * 0.05 * 2.0 * p["volume"] * 4   # громкость как у sfxr, чуть громче
        out.append(max(-1.0, min(1.0, ssample)))
    return out


# --- пресеты -----------------------------------------------------------------------------------
# Первые семь — генераторы из оригинального sfxr. Остальные — под нашу игру про офис.

def _r(rng, x):
    return rng.random() * x


def pickup(rng, **_):
    p = {"base_freq": 0.4 + _r(rng, 0.5), "env_sustain": _r(rng, 0.1), "env_decay": 0.1 + _r(rng, 0.4),
         "env_punch": 0.3 + _r(rng, 0.3)}
    if rng.random() < 0.5:
        p.update(arp_speed=0.5 + _r(rng, 0.2), arp_mod=0.2 + _r(rng, 0.4))
    return p


def laser(rng, **_):
    p = {"wave_type": rng.choice([SQUARE, SAW, SINE, SQUARE, SAW])}
    p.update(base_freq=0.5 + _r(rng, 0.5), freq_ramp=-0.15 - _r(rng, 0.2))
    p["freq_limit"] = max(0.2, p["base_freq"] - 0.2 - _r(rng, 0.6))
    if rng.random() < 0.33:
        p.update(base_freq=0.3 + _r(rng, 0.6), freq_limit=_r(rng, 0.1), freq_ramp=-0.35 - _r(rng, 0.3))
    if rng.random() < 0.5:
        p.update(duty=_r(rng, 0.5), duty_ramp=_r(rng, 0.2))
    else:
        p.update(duty=0.4 + _r(rng, 0.5), duty_ramp=-_r(rng, 0.7))
    p.update(env_sustain=0.1 + _r(rng, 0.2), env_decay=_r(rng, 0.4))
    if rng.random() < 0.5:
        p["env_punch"] = _r(rng, 0.3)
    if rng.random() < 0.33:
        p.update(pha_offset=_r(rng, 0.2), pha_ramp=-_r(rng, 0.2))
    if rng.random() < 0.5:
        p["hpf_freq"] = _r(rng, 0.3)
    return p


def explosion(rng, **_):
    p = {"wave_type": NOISE}
    if rng.random() < 0.5:
        p.update(base_freq=0.1 + _r(rng, 0.4), freq_ramp=-0.1 + _r(rng, 0.4))
    else:
        p.update(base_freq=0.2 + _r(rng, 0.7), freq_ramp=-0.2 - _r(rng, 0.2))
    p["base_freq"] **= 2
    if rng.random() < 0.2:
        p["freq_ramp"] = 0.0
    if rng.random() < 0.33:
        p["repeat_speed"] = 0.3 + _r(rng, 0.5)
    p.update(env_sustain=0.1 + _r(rng, 0.3), env_decay=_r(rng, 0.5), env_punch=0.2 + _r(rng, 0.6))
    if rng.random() < 0.5:
        p.update(pha_offset=-0.3 + _r(rng, 0.9), pha_ramp=-_r(rng, 0.3))
    if rng.random() < 0.5:
        p.update(vib_strength=_r(rng, 0.7), vib_speed=_r(rng, 0.6))
    if rng.random() < 0.33:
        p.update(arp_speed=0.6 + _r(rng, 0.3), arp_mod=0.8 - _r(rng, 1.6))
    return p


def powerup(rng, **_):
    p = {"wave_type": SAW} if rng.random() < 0.5 else {"duty": _r(rng, 0.6)}
    if rng.random() < 0.5:
        p.update(base_freq=0.2 + _r(rng, 0.3), freq_ramp=0.1 + _r(rng, 0.4), repeat_speed=0.4 + _r(rng, 0.4))
    else:
        p.update(base_freq=0.2 + _r(rng, 0.3), freq_ramp=0.05 + _r(rng, 0.2))
        if rng.random() < 0.5:
            p.update(vib_strength=_r(rng, 0.7), vib_speed=_r(rng, 0.6))
    p.update(env_sustain=_r(rng, 0.4), env_decay=0.1 + _r(rng, 0.4))
    return p


def hit(rng, **_):
    w = rng.choice([SQUARE, SAW, NOISE])
    p = {"wave_type": w, "base_freq": 0.2 + _r(rng, 0.6), "freq_ramp": -0.3 - _r(rng, 0.4),
         "env_sustain": _r(rng, 0.1), "env_decay": 0.1 + _r(rng, 0.2)}
    if w == SQUARE:
        p["duty"] = _r(rng, 0.6)
    if rng.random() < 0.5:
        p["hpf_freq"] = _r(rng, 0.3)
    return p


def jump(rng, **_):
    p = {"duty": _r(rng, 0.6), "base_freq": 0.3 + _r(rng, 0.3), "freq_ramp": 0.1 + _r(rng, 0.2),
         "env_sustain": 0.1 + _r(rng, 0.3), "env_decay": 0.1 + _r(rng, 0.2)}
    if rng.random() < 0.5:
        p["hpf_freq"] = _r(rng, 0.3)
    if rng.random() < 0.5:
        p["lpf_freq"] = 1.0 - _r(rng, 0.6)
    return p


def blip(rng, **_):
    w = rng.choice([SQUARE, SAW])
    p = {"wave_type": w, "base_freq": 0.2 + _r(rng, 0.4), "env_sustain": 0.1 + _r(rng, 0.1),
         "env_decay": _r(rng, 0.2), "hpf_freq": 0.1}
    if w == SQUARE:
        p["duty"] = _r(rng, 0.6)
    return p


def talk(rng, pitch=None, **_):
    """Писк одной «буквы» реплики (как в Undertale/Animal Crossing). Короткий, без щелчка.
    pitch 0..1 — «голос» персонажа: задайте каждому NPC свой и храните в данных."""
    base = pitch if pitch is not None else 0.35 + _r(rng, 0.35)
    return {"wave_type": rng.choice([SQUARE, SQUARE, SINE]), "duty": 0.3 + _r(rng, 0.3),
            "base_freq": base, "env_attack": 0.02, "env_sustain": 0.12 + _r(rng, 0.04),
            "env_decay": 0.1 + _r(rng, 0.05), "lpf_freq": 0.7 + _r(rng, 0.2), "hpf_freq": 0.05,
            "volume": 0.35}


def select(rng, **_):
    """Перемещение по меню: очень короткий мягкий тик."""
    return {"wave_type": SINE if rng.random() < 0.5 else SQUARE, "duty": 0.5,
            "base_freq": 0.45 + _r(rng, 0.2), "env_sustain": 0.05 + _r(rng, 0.03),
            "env_decay": 0.08 + _r(rng, 0.06), "hpf_freq": 0.1, "volume": 0.35}


def confirm(rng, **_):
    """Подтверждение: два тона вверх."""
    return {"wave_type": SQUARE, "duty": 0.2 + _r(rng, 0.3), "base_freq": 0.35 + _r(rng, 0.15),
            "arp_speed": 0.55 + _r(rng, 0.1), "arp_mod": 0.3 + _r(rng, 0.2),
            "env_sustain": 0.15 + _r(rng, 0.05), "env_decay": 0.15 + _r(rng, 0.1),
            "env_punch": 0.2, "hpf_freq": 0.05}


def cancel(rng, **_):
    """Отмена / «нельзя»: два тона вниз."""
    return {"wave_type": SQUARE, "duty": 0.3 + _r(rng, 0.3), "base_freq": 0.35 + _r(rng, 0.1),
            "arp_speed": 0.55 + _r(rng, 0.1), "arp_mod": -0.25 - _r(rng, 0.1),
            "env_sustain": 0.12 + _r(rng, 0.05), "env_decay": 0.15 + _r(rng, 0.1), "hpf_freq": 0.05}


def footstep(rng, **_):
    """Шаг по ковролину: глухой короткий шум без высоких."""
    return {"wave_type": NOISE, "base_freq": 0.05 + _r(rng, 0.08), "freq_ramp": -0.1 - _r(rng, 0.2),
            "env_sustain": 0.02 + _r(rng, 0.03), "env_decay": 0.08 + _r(rng, 0.06),
            "lpf_freq": 0.25 + _r(rng, 0.15), "volume": 0.5}


PRESETS = {f.__name__: f for f in (pickup, laser, explosion, powerup, hit, jump, blip,
                                    talk, select, confirm, cancel, footstep)}


# --- сборка звука и мелодии ----------------------------------------------------------------------

def jingle(notes, step=0.09, wave_type=SQUARE, duty=0.25):
    """Мелодия из нот (полутоны от ля первой октавы, None — пауза). Для «квест выполнен»."""
    out = []
    for n in notes:
        seg = int(step * RATE)
        if n is None:
            out += [0.0] * seg
            continue
        freq = 440.0 * 2 ** (n / 12)
        # В sfxr период = 100/(bf^2+0.001) шагов, шагов 8 на сэмпл: freq = 8*RATE/период.
        bf = math.sqrt(max(0.0, 100.0 * freq / (8 * RATE) - 0.001))
        tone = synth({"wave_type": wave_type, "duty": duty, "base_freq": bf,
                      "env_sustain": math.sqrt(step * 0.6 * RATE / 100000),
                      "env_decay": math.sqrt(step * 0.8 * RATE / 100000), "env_punch": 0.3})
        out += (tone + [0.0] * seg)[:seg] if len(tone) < seg else tone[:seg]
    return out


JINGLES = {
    # До-мажорное «та-да»: ступени от ля (0): до=3, ми=7, соль=10, до=15
    "questdone": [3, 7, 10, 15, None, 10, 15, 15],
    "newquest": [10, 15, None, 15],
    "fail": [7, 6, 5, 4, None, 3],
}


def trim_and_normalize(samples, peak=0.85, thresh=0.002):
    """Срезать тишину по краям (генератор её не даёт, но фильтры дают хвост) и выровнять пик."""
    i = next((k for k, s in enumerate(samples) if abs(s) > thresh), 0)
    j = next((k for k in range(len(samples) - 1, -1, -1) if abs(samples[k]) > thresh), len(samples) - 1)
    samples = samples[i:j + 1] or [0.0]
    m = max(abs(s) for s in samples) or 1.0
    fade = min(len(samples), int(0.004 * RATE))          # 4 мс затухания в конце — без щелчка
    out = [s * peak / m for s in samples]
    for k in range(fade):
        out[-1 - k] *= k / fade
    return out


def write_wav(path, samples):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("preset", nargs="?", help="пресет или мелодия; --list — перечень")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--count", type=int, default=1, help="сколько вариантов")
    ap.add_argument("--seed", type=int, help="зерно; без него случайное (пишется в .json)")
    ap.add_argument("--pitch", type=float, help="для talk: высота голоса 0..1")
    ap.add_argument("--params", help="пересобрать звук из сохранённого .json")
    ap.add_argument("--name", help="имя файла/каталога вместо имени пресета")
    ap.add_argument("--out", default="audio_out", help="куда (относительно game/)")
    a = ap.parse_args()

    if a.list or not (a.preset or a.params):
        print("пресеты:", ", ".join(PRESETS))
        print("мелодии:", ", ".join(JINGLES))
        return
    name = a.name or a.preset or Path(a.params).stem
    out = GAME / a.out / name
    out.mkdir(parents=True, exist_ok=True)

    if a.params:
        p = json.loads(Path(a.params).read_text(encoding="utf-8"))
        seed = p.pop("_seed", 0)
        p.pop("_preset", None)
        samples = trim_and_normalize(synth(p, random.Random(seed)))
        write_wav(out / f"{name}.wav", samples)
        (out / f"{name}.json").write_text(json.dumps({**p, "_seed": seed}, indent=1) + "\n")
        print(out / f"{name}.wav")
        return

    if a.preset in JINGLES:
        samples = trim_and_normalize(jingle(JINGLES[a.preset]))
        write_wav(out / f"{name}.wav", samples)
        print(out / f"{name}.wav")
        return
    if a.preset not in PRESETS:
        sys.exit(f"нет пресета {a.preset!r}; есть: {', '.join(PRESETS)}, {', '.join(JINGLES)}")

    base_seed = a.seed if a.seed is not None else random.randrange(2 ** 31)
    for i in range(a.count):
        seed = base_seed + i
        rng = random.Random(seed)
        p = PRESETS[a.preset](rng, pitch=a.pitch)
        samples = trim_and_normalize(synth(p, random.Random(seed)))
        stem = f"{name}_{i:02d}" if a.count > 1 else name
        write_wav(out / f"{stem}.wav", samples)
        (out / f"{stem}.json").write_text(
            json.dumps({**p, "_preset": a.preset, "_seed": seed}, indent=1) + "\n")
        print(f"{out / stem}.wav  {len(samples) / RATE:.2f} с")


if __name__ == "__main__":
    main()
