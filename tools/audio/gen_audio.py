#!/usr/bin/env python3
"""Звуки и музыка для LevelUp нейросетями: ComfyUI на arrakis -> ffmpeg -> WAV/OGG для Godot.

Полное руководство — docs/audio-pipeline.md. Здесь только как вызывать.

  # звук (Stable Audio 3 Small SFX), 4 варианта по 2 с -> WAV моно, без тишины
  python3 tools/audio/gen_audio.py door_open "office door opening, wooden, creak, click" --model sfx --seconds 2

  # фоновая музыка (MiniMax Music 3), 60 с, зациклить -> OGG
  python3 tools/audio/gen_audio.py bgm_office "calm lo-fi office background, soft electric piano, light drums, 85 BPM" \\
      --model minimax --seconds 60 --loop --count 2

  # то же на других моделях — для сравнения на слух
  python3 tools/audio/gen_audio.py bgm_office_sa "..." --model sa-music --seconds 60 --loop
  python3 tools/audio/gen_audio.py bgm_office_ace "..." --model ace --seconds 60 --loop

Короткие «игровые» писки (текст, меню, монетка) — не сюда, а в tools/audio/sfxr.py:
он делает их мгновенно и лучше.

В audio_out/<имя>/ появятся:
  NN.wav | NN.ogg   готовый звук (sfx — WAV моно 44.1 кГц; музыка — OGG Vorbis стерео)
  raw_NN.flac       что выдала модель, без обработки
  sheet.png         спектрограммы всех вариантов — единственный способ «увидеть» звук
                    (агенту: тишина — чёрная полоса, шум — ровная серая заливка)
  meta.json         промпт, зерно, модель, длительность, пик и громкость каждого варианта

Требует: Pillow и ffmpeg (системный или `pip install imageio-ffmpeg`).
ComfyUI: COMFY_URL (по умолчанию http://192.168.1.202:8188), будить — COMFY_WAKE_CMD.
"""

import argparse
import json
import os
import random
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "art"))
import gen_sprite as comfy  # noqa: E402  — общий клиент ComfyUI: ensure_up, _post_json, _get

GAME = Path(__file__).resolve().parents[2]

# Модели. Файлы лежат на arrakis в /srv/models/comfy (tools/audio/install_arrakis.sh).
MODELS = {
    # Stable Audio 3 (Stability Community License: бесплатно при выручке < $1 млн)
    "sfx":      {"kind": "sfx",   "ckpt": "stable_audio_3_small_sfx.safetensors", "seconds": 3},
    "sa-music": {"kind": "music", "ckpt": "stable_audio_3_medium.safetensors", "seconds": 60},
    # MiniMax Music 3 (Apache 2.0 на перепаковке Comfy-Org), ComfyUI >= 0.33
    "minimax":  {"kind": "music", "seconds": 60},
    # ACE-Step 1.5 turbo (всё в одном файле), MIT/Apache
    "ace":      {"kind": "music", "ckpt": "ace_step_1.5_turbo_aio.safetensors", "seconds": 60},
}


# --- графы ComfyUI -----------------------------------------------------------------------

def graph_stable_audio(ckpt, prompt, negative, seconds, count, seed):
    """Stable Audio 3: как в шаблоне ComfyUI «Stable Audio 3 Medium», без LLM-переписчика
    промпта. Дистиллят: 8 шагов, lcm, cfg 1."""
    return {
        "ckpt": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": ckpt}},
        "clip": {"class_type": "CLIPLoader",
                 "inputs": {"clip_name": "t5gemma_b_b_ul2.safetensors", "type": "stable_audio", "device": "default"}},
        "pos": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["clip", 0], "text": prompt}},
        "neg": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["clip", 0], "text": negative}},
        "latent": {"class_type": "EmptyLatentAudio", "inputs": {"seconds": float(seconds), "batch_size": count}},
        "run": {"class_type": "KSampler",
                "inputs": {"model": ["ckpt", 0], "positive": ["pos", 0], "negative": ["neg", 0],
                           "latent_image": ["latent", 0], "seed": seed, "steps": 8, "cfg": 1.0,
                           "sampler_name": "lcm", "scheduler": "simple", "denoise": 1.0}},
        "decode": {"class_type": "VAEDecodeAudio", "inputs": {"samples": ["run", 0], "vae": ["ckpt", 2]}},
        "save": {"class_type": "SaveAudio", "inputs": {"audio": ["decode", 0], "filename_prefix": "levelup/audio"}},
    }


def graph_ace(ckpt, prompt, lyrics, seconds, count, seed, bpm, key):
    """ACE-Step 1.5 turbo: шаблон «ACE-Step 1.5 checkpoint». Негатив — обнулённый позитив."""
    return {
        "ckpt": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": ckpt}},
        "pos": {"class_type": "TextEncodeAceStepAudio1.5",
                "inputs": {"clip": ["ckpt", 1], "tags": prompt, "lyrics": lyrics, "seed": seed, "bpm": bpm,
                           "duration": float(seconds), "timesignature": "4", "language": "en",
                           "keyscale": key, "generate_audio_codes": True, "cfg_scale": 2.0,
                           "temperature": 0.85, "top_p": 0.9, "top_k": 0, "min_p": 0.0}},
        "neg": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["pos", 0]}},
        "shift": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["ckpt", 0], "shift": 3.0}},
        "latent": {"class_type": "EmptyAceStep1.5LatentAudio", "inputs": {"seconds": float(seconds), "batch_size": count}},
        "run": {"class_type": "KSampler",
                "inputs": {"model": ["shift", 0], "positive": ["pos", 0], "negative": ["neg", 0],
                           "latent_image": ["latent", 0], "seed": seed, "steps": 8, "cfg": 1.0,
                           "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0}},
        "decode": {"class_type": "VAEDecodeAudio", "inputs": {"samples": ["run", 0], "vae": ["ckpt", 2]}},
        "save": {"class_type": "SaveAudio", "inputs": {"audio": ["decode", 0], "filename_prefix": "levelup/audio"}},
    }


def graph_minimax(prompt, lyrics, seconds, seed):
    """MiniMax Music 3: шаблон ComfyUI «Text to Music (MiniMax Music 3)», ComfyUI >= 0.33.

    Устроена в два этапа: языковая модель (энкодер) по промпту и зерну сочиняет
    «акустический план» и сама решает длину (max_duration — только потолок),
    потом диффузия его озвучивает. Поэтому варианты с разной композицией — это
    разные зёрна, то есть отдельные задания, а не batch: в batch у всех один план."""
    return {
        "unet": {"class_type": "UNETLoader",
                 "inputs": {"unet_name": "minimax_music3_dit_fp16.safetensors", "weight_dtype": "default"}},
        "clip": {"class_type": "CLIPLoader",
                 "inputs": {"clip_name": "minimax_music3_text_encoder_pruned_bf16.safetensors",
                            "type": "minimax", "device": "default"}},
        "vae": {"class_type": "VAELoader", "inputs": {"vae_name": "minimax_music3_dav.safetensors"}},
        "pos": {"class_type": "MiniMaxMusic3TextEncode",
                "inputs": {"clip": ["clip", 0], "caption": prompt, "lyrics": lyrics, "seed": seed,
                           "max_duration": float(seconds), "cfg_scale": 1.7, "top_k": 50}},
        "neg": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["pos", 0]}},
        "latent": {"class_type": "EmptyMiniMaxMusic3LatentAudio", "inputs": {"seconds": ["pos", 1], "batch_size": 1}},
        "run": {"class_type": "KSampler",
                "inputs": {"model": ["unet", 0], "positive": ["pos", 0], "negative": ["neg", 0],
                           "latent_image": ["latent", 0], "seed": seed, "steps": 30, "cfg": 1.7,
                           "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0}},
        "decode": {"class_type": "VAEDecodeAudio", "inputs": {"samples": ["run", 0], "vae": ["vae", 0]}},
        "save": {"class_type": "SaveAudio", "inputs": {"audio": ["decode", 0], "filename_prefix": "levelup/audio"}},
    }


def run_graph(graph, timeout=1800):
    """Ставит граф в очередь и ждёт; возвращает список (байты FLAC) и секунды."""
    pid = comfy._post_json("/prompt", {"prompt": graph, "client_id": "levelup-gen-audio"})["prompt_id"]
    t0 = time.time()
    while True:
        hist = json.loads(comfy._get(f"/history/{pid}"))
        if pid in hist:
            status = hist[pid].get("status", {})
            if status.get("status_str") == "error":
                msgs = [m for m in status.get("messages", []) if m[0] == "execution_error"]
                sys.exit(f"ComfyUI вернул ошибку: {json.dumps(msgs, ensure_ascii=False)[:2000]}")
            if status.get("completed"):
                break
        if time.time() - t0 > timeout:
            sys.exit(f"задание {pid} не закончилось за {timeout} с")
        time.sleep(2)
    import urllib.parse
    files = []
    for node in hist[pid]["outputs"].values():
        for a in node.get("audio", []):
            q = urllib.parse.urlencode({k: a[k] for k in ("filename", "subfolder", "type")})
            files.append(comfy._get(f"/view?{q}", 120))
    return files, time.time() - t0


# --- ffmpeg: обработка под Godot ---------------------------------------------------------

def ffmpeg_exe():
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        sys.exit("нужен ffmpeg: поставьте системный или `pip install imageio-ffmpeg`")


def ff(*args):
    r = subprocess.run([ffmpeg_exe(), "-hide_banner", "-nostdin", "-y", *args], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"ffmpeg упал: {' '.join(args)}\n{r.stderr[-1500:]}")
    return r.stderr


def duration(path):
    m = re.search(r"Duration: (\d+):(\d+):([\d.]+)", ff("-i", str(path), "-f", "null", "-"))
    return int(m[1]) * 3600 + int(m[2]) * 60 + float(m[3]) if m else 0.0


def levels(path):
    """Пик (dBFS) и средняя громкость (dBFS) — чтобы без прослушивания видеть тишину и клиппинг."""
    err = ff("-i", str(path), "-af", "volumedetect", "-f", "null", "-")
    peak = re.search(r"max_volume: (-?[\d.]+) dB", err)
    mean = re.search(r"mean_volume: (-?[\d.]+) dB", err)
    return (float(peak[1]) if peak else None), (float(mean[1]) if mean else None)


def finish_sfx(raw, out):
    """Звук: моно, 44.1 кГц, без гула ниже 30 Гц, тишина по краям срезана, пик -1 dBFS,
    10 мс затухания в конце.

    Тишину в начале срезаем обязательно: звук играется в момент события, и 50 мс
    задержки уже слышны как «не попал». Моно — потому что в 2D Godot сам разносит
    по каналам (AudioStreamPlayer2D), а стерео из модели только мешает."""
    trim = "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.005"
    tmp = out.with_suffix(".tmp.wav")
    ff("-i", str(raw), "-ac", "1", "-ar", "44100",
       "-af", f"highpass=f=30,{trim},areverse,{trim},areverse", "-c:a", "pcm_s16le", str(tmp))
    peak, _ = levels(tmp)
    gain = -1.0 - (peak if peak is not None else 0.0)
    d = duration(tmp)
    ff("-i", str(tmp), "-af", f"volume={gain:.2f}dB,afade=t=out:st={max(0.0, d - 0.01):.3f}:d=0.01",
       "-c:a", "pcm_s16le", str(out))
    tmp.unlink()


def finish_music(raw, out, loop, xfade=2.0):
    """Музыка: OGG Vorbis (его Godot зацикливает без щелчка), громкость -16 LUFS.

    loop: последние xfade секунд плавно накладываются на первые, а сам файл
    укорачивается на xfade. Тогда конец файла ровно продолжается его началом,
    и в Godot достаточно включить loop у импорта."""
    d = duration(raw)
    norm = "loudnorm=I=-16:TP=-1.5:LRA=11"
    if loop and d > 4 * xfade:
        fc = (f"[0]asplit=3[a][b][c];"
              f"[a]atrim=0:{xfade},asetpts=PTS-STARTPTS,afade=t=in:d={xfade}:curve=qsin[h];"
              f"[b]atrim={d - xfade}:{d},asetpts=PTS-STARTPTS,afade=t=out:d={xfade}:curve=qsin[t];"
              f"[h][t]amix=inputs=2:normalize=0[m];"
              f"[c]atrim={xfade}:{d - xfade},asetpts=PTS-STARTPTS[body];"
              f"[m][body]concat=n=2:v=0:a=1,{norm}[out]")
        ff("-i", str(raw), "-filter_complex", fc, "-map", "[out]", "-ar", "44100",
           "-c:a", "libvorbis", "-q:a", "6", str(out))
    else:
        ff("-i", str(raw), "-af", norm, "-ar", "44100", "-c:a", "libvorbis", "-q:a", "6", str(out))


def spectrogram(path, png, label):
    """Спектрограмма с подписью. drawtext не у всех сборок ffmpeg, поэтому подпись — Pillow."""
    from PIL import Image, ImageDraw
    ff("-i", str(path), "-lavfi", "showspectrumpic=s=640x160:legend=0:color=intensity", str(png))
    im = Image.open(png).convert("RGB")
    ImageDraw.Draw(im).text((4, 2), label, fill=(255, 255, 255))
    im.save(png)


# --- главное ------------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name", help="имя набора: латиница, станет каталогом audio_out/<name>/")
    ap.add_argument("description", help="что должно звучать, по-английски")
    ap.add_argument("--model", choices=MODELS, default="sfx")
    ap.add_argument("--seconds", type=float, help="длина генерации; по умолчанию sfx 3 с, музыка 60 с")
    ap.add_argument("--count", type=int, help="вариантов за раз; по умолчанию sfx 4, музыка 2")
    ap.add_argument("--seed", type=int)
    ap.add_argument("--negative", default="", help="чего не должно быть (только Stable Audio)")
    ap.add_argument("--lyrics", default="[Instrumental]", help="текст песни (ace/minimax); по умолчанию без слов")
    ap.add_argument("--bpm", type=int, default=90, help="темп (ace)")
    ap.add_argument("--key", default="C major", help="тональность (ace), например 'A minor'")
    ap.add_argument("--loop", action="store_true", help="музыка: сделать бесшовную петлю")
    ap.add_argument("--out", default="audio_out", help="куда (относительно game/)")
    a = ap.parse_args()

    m = MODELS[a.model]
    seconds = a.seconds or m["seconds"]
    count = max(1, min(8, a.count or (4 if m["kind"] == "sfx" else 2)))
    seed = a.seed if a.seed is not None else random.randrange(2 ** 31)
    ffmpeg_exe()                                         # упасть сразу, а не после генерации

    if a.model in ("sfx", "sa-music"):
        graphs = [graph_stable_audio(m["ckpt"], a.description, a.negative, seconds, count, seed)]
    elif a.model == "ace":
        # Как и у MiniMax, план музыки сочиняет языковая модель по зерну — варианты
        # отдельными заданиями.
        graphs = [graph_ace(m["ckpt"], a.description, a.lyrics, seconds, 1, seed + i, a.bpm, a.key)
                  for i in range(count)]
    else:
        graphs = [graph_minimax(a.description, a.lyrics, seconds, seed + i) for i in range(count)]

    out = GAME / a.out / a.name
    out.mkdir(parents=True, exist_ok=True)
    comfy.ensure_up()
    print(f"генерирую {count} шт. по {seconds:g} с, {a.model}, зерно {seed}: {a.description}", file=sys.stderr)
    raws, secs = [], 0.0
    for g in graphs:
        r, t = run_graph(g)
        raws += r
        secs += t

    from PIL import Image
    results, pngs = [], []
    ext = "wav" if m["kind"] == "sfx" else "ogg"
    for i, data in enumerate(raws):
        raw = out / f"raw_{i:02d}.flac"
        raw.write_bytes(data)
        dst = out / f"{i:02d}.{ext}"
        if m["kind"] == "sfx":
            finish_sfx(raw, dst)
        else:
            finish_music(raw, dst, a.loop)
        peak, mean = levels(dst)
        png = out / f".spec_{i:02d}.png"
        spectrogram(dst, png, f"{i:02d}  {duration(dst):.2f} s")
        pngs.append(Image.open(png).convert("RGB"))
        png.unlink()
        results.append({"file": dst.name, "seconds": round(duration(dst), 2), "peak_db": peak, "mean_db": mean,
                        "quiet": mean is not None and mean < -45})
    sheet = Image.new("RGB", (max(p.width for p in pngs), sum(p.height for p in pngs)))
    y = 0
    for p in pngs:
        sheet.paste(p, (0, y))
        y += p.height
    sheet.save(out / "sheet.png")
    (out / "meta.json").write_text(json.dumps({
        "name": a.name, "description": a.description, "model": a.model, "seed": seed, "seconds": seconds,
        "negative": a.negative, "lyrics": a.lyrics if m["kind"] == "music" else None,
        "bpm": a.bpm if a.model == "ace" else None, "key": a.key if a.model == "ace" else None,
        "loop": a.loop, "results": results, "gen_seconds": round(secs, 1),
        "created": time.strftime("%Y-%m-%d %H:%M:%S"),
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    quiet = [r["file"] for r in results if r["quiet"]]
    print(f"готово за {secs:.0f} с: {out.relative_to(GAME)}/  " + ", ".join(
        f"{r['file']} {r['seconds']}с" for r in results) + (f"  ТИХИЕ: {quiet}" if quiet else ""))


if __name__ == "__main__":
    main()
