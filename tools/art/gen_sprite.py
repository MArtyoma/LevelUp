#!/usr/bin/env python3
"""Генерация спрайтов для LevelUp: ComfyUI на arrakis -> pixelize -> PNG под сетку.

Модель: FLUX.2 [klein] 4B + LoRA Limbicnation/pixel-art-lora (обе Apache 2.0).
Полное руководство — docs/art-pipeline.md. Здесь только как вызывать.

  # четыре варианта NPC 16x32, результаты в art_out/npc_hr/
  python3 tools/art/gen_sprite.py npc_hr "young woman, HR manager, red cardigan, holding folder"

  # предмет 16x16 по центру
  python3 tools/art/gen_sprite.py coffee "coffee machine" --kind prop

  # вариант по образцу: та же фигура, другая одежда (правка через klein)
  python3 tools/art/gen_sprite.py npc_it "same character but with green hoodie and headphones" \\
      --ref art_out/npc_hr/raw_00.png

В art_out/<имя>/ появятся:
  raw_NN.png      что нарисовала модель (512x512) — его же можно подать в --ref
  sprite_NN.png   готовый спрайт под сетку игры
  sheet.png       все варианты рядом, увеличенные, на шахматке — смотреть сюда
  meta.json       промпт, зерно и параметры — чтобы повторить результат

Спрайт в игру кладёт человек (или агент), выбрав лучший вариант:
  cp art_out/npc_hr/sprite_02.png assets/sprites/npc_hr.png

Требует только Pillow. ComfyUI: COMFY_URL (по умолчанию http://192.168.1.202:8188).
"""

import argparse
import json
import os
import random
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from io import BytesIO
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pixelize  # noqa: E402

URL = os.environ.get("COMFY_URL", "http://192.168.1.202:8188").rstrip("/")
# Команда, которой будить спящий ComfyUI (он гаснет через 3 минуты простоя).
# Например: COMFY_WAKE_CMD="ssh root@192.168.1.202 systemctl start comfyui"
WAKE_CMD = os.environ.get("COMFY_WAKE_CMD", "")
GAME = Path(__file__).resolve().parents[2]

UNET = "flux-2-klein-4b.safetensors"
CLIP = "qwen_3_4b.safetensors"
VAE = "flux2-vae.safetensors"
# Исправленная копия LoRA: в оригинале 6 ключей модуляции названы по-diffusers,
# и ComfyUI молча их пропускал (docs/art-pipeline.md, «LoRA»).
LORA = "pixel-art-sprite-klein4b-fixed.safetensors"

# Слова-триггеры LoRA — без «pixel art sprite ... game asset» стиль не включается.
# «transparent background» из карточки LoRA НЕ используем: модель рисует вместо
# прозрачности шахматку, и та сливается со светлой одеждой. Сплошной ядовитый
# фон, которого нет в офисной одежде, вырезается чисто (docs/art-pipeline.md).
BACKGROUNDS = {
    "green": "isolated on a solid flat pure green background",
    "magenta": "isolated on a solid flat pure magenta background",
}
# Зелёное (растения, толстовка) на зелёном фоне вырезается вместе с фоном —
# такие описания автоматически рисуются на пурпурном.
GREENISH = ("green", "plant", "cactus", "leaf", "leaves", "tree", "grass", "fern", "lime", "olive")
KINDS = {
    #          размер  якорь     что дописать к описанию
    "character": ((16, 32), "bottom", "simple minimalist low-res sprite, tiny black dot eyes, "
                  "thick dark outline, flat colors, few colors, chibi, big head, short body, "
                  "single character, full body, front view, standing, facing the viewer"),
    "prop":      ((16, 16), "center", "single object, centered, three-quarter top-down view"),
    "portrait":  ((32, 32), "center", "head and shoulders portrait, front view"),
}


# --- ComfyUI ------------------------------------------------------------------------

def _get(path, timeout=10):
    with urllib.request.urlopen(URL + path, timeout=timeout) as r:
        return r.read()


def _post_json(path, obj):
    req = urllib.request.Request(URL + path, data=json.dumps(obj).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def ensure_up(wait=240):
    """ComfyUI спит, если три минуты никто не рисовал. Будим и ждём порт."""
    try:
        _get("/system_stats", 5)
        return
    except (urllib.error.URLError, OSError):
        pass
    if not WAKE_CMD:
        sys.exit(f"ComfyUI на {URL} не отвечает (скорее всего спит).\n"
                 "Разбудить: на arrakis `systemctl start comfyui`, или задайте\n"
                 "COMFY_WAKE_CMD=\"ssh root@192.168.1.202 systemctl start comfyui\".")
    print(f"ComfyUI спит, бужу: {WAKE_CMD}", file=sys.stderr)
    subprocess.run(WAKE_CMD, shell=True, check=True)
    t0 = time.time()
    while time.time() - t0 < wait:
        try:
            _get("/system_stats", 5)
            print(f"поднялся за {time.time() - t0:.0f} с", file=sys.stderr)
            return
        except (urllib.error.URLError, OSError):
            time.sleep(3)
    sys.exit(f"ComfyUI не поднялся за {wait} с — смотрите `journalctl -u comfyui` на arrakis")


def upload(path):
    """Кладёт картинку-образец во входной каталог ComfyUI, возвращает её имя там."""
    boundary = uuid.uuid4().hex
    data = Path(path).read_bytes()
    name = f"levelup_{uuid.uuid4().hex[:8]}_{Path(path).name}"
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"{name}\"\r\n"
            f"Content-Type: image/png\r\n\r\n").encode() + data + \
           f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(URL + "/upload/image", data=body,
                                 headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())["name"]


def build_graph(prompt, seed, count, size, lora_strength, ref_name=None, lora_file=LORA):
    """Граф в формате API ComfyUI. Повторяет шаблон «Flux.2 Klein 4B Distilled»:
    4 шага, CFG 1, негатив — обнулённый позитив. С ref_name — режим правки:
    образец кодируется VAE и цепляется к условию через ReferenceLatent."""
    w, h = size
    g = {
        "unet": {"class_type": "UNETLoader", "inputs": {"unet_name": UNET, "weight_dtype": "default"}},
        "lora": {"class_type": "LoraLoaderModelOnly",
                 "inputs": {"model": ["unet", 0], "lora_name": lora_file, "strength_model": lora_strength}},
        "clip": {"class_type": "CLIPLoader", "inputs": {"clip_name": CLIP, "type": "flux2", "device": "default"}},
        "vae": {"class_type": "VAELoader", "inputs": {"vae_name": VAE}},
        "pos": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["clip", 0], "text": prompt}},
        "neg": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["pos", 0]}},
        "latent": {"class_type": "EmptyFlux2LatentImage", "inputs": {"width": w, "height": h, "batch_size": count}},
        "sched": {"class_type": "Flux2Scheduler", "inputs": {"steps": 4, "width": w, "height": h}},
        "sampler": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "noise": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "guider": {"class_type": "CFGGuider",
                   "inputs": {"model": ["lora", 0], "positive": ["pos", 0], "negative": ["neg", 0], "cfg": 1.0}},
        "run": {"class_type": "SamplerCustomAdvanced",
                "inputs": {"noise": ["noise", 0], "guider": ["guider", 0], "sampler": ["sampler", 0],
                           "sigmas": ["sched", 0], "latent_image": ["latent", 0]}},
        "decode": {"class_type": "VAEDecode", "inputs": {"samples": ["run", 0], "vae": ["vae", 0]}},
        "save": {"class_type": "SaveImage", "inputs": {"images": ["decode", 0], "filename_prefix": "levelup/sprite"}},
    }
    if ref_name:
        g["ref_img"] = {"class_type": "LoadImage", "inputs": {"image": ref_name}}
        g["ref_scaled"] = {"class_type": "ImageScale",
                           "inputs": {"image": ["ref_img", 0], "upscale_method": "nearest-exact",
                                      "width": w, "height": h, "crop": "center"}}
        g["ref_lat"] = {"class_type": "VAEEncode", "inputs": {"pixels": ["ref_scaled", 0], "vae": ["vae", 0]}}
        g["pos_ref"] = {"class_type": "ReferenceLatent",
                        "inputs": {"conditioning": ["pos", 0], "latent": ["ref_lat", 0]}}
        g["neg_ref"] = {"class_type": "ReferenceLatent",
                        "inputs": {"conditioning": ["neg", 0], "latent": ["ref_lat", 0]}}
        g["guider"]["inputs"]["positive"] = ["pos_ref", 0]
        g["guider"]["inputs"]["negative"] = ["neg_ref", 0]
    return g


def run_graph(graph, timeout=900):
    """Ставит граф в очередь, ждёт, возвращает список картинок PIL."""
    pid = _post_json("/prompt", {"prompt": graph, "client_id": "levelup-gen-sprite"})["prompt_id"]
    t0 = time.time()
    while True:
        hist = json.loads(_get(f"/history/{pid}"))
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
    images = []
    for node in hist[pid]["outputs"].values():
        for im in node.get("images", []):
            q = urllib.parse.urlencode({k: im[k] for k in ("filename", "subfolder", "type")})
            images.append(Image.open(BytesIO(_get(f"/view?{q}", 60))).convert("RGB"))
    return images, time.time() - t0


# --- главное ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name", help="имя набора: латиница, станет каталогом art_out/<name>/")
    ap.add_argument("description", help="что нарисовать, по-английски: кто, одежда, что в руках")
    ap.add_argument("--kind", choices=KINDS, default="character")
    ap.add_argument("--size", help="ШxВ спрайта; по умолчанию от --kind (16x32, 16x16, 32x32)")
    ap.add_argument("--count", type=int, default=4, help="сколько вариантов за раз (1-8)")
    ap.add_argument("--seed", type=int, help="зерно; без него случайное (записывается в meta.json)")
    ap.add_argument("--ref", help="картинка-образец: рисовать «как эту, но ...» (режим правки)")
    ap.add_argument("--palette", help="палитра .hex/.png; по умолчанию assets/palette.hex, если есть")
    ap.add_argument("--colors", type=int, default=16, help="цветов, если палитры нет")
    ap.add_argument("--outline", action="store_true", help="дорисовать тёмную обводку в 1 px")
    ap.add_argument("--lora", type=float, default=1.0, help="сила LoRA (0.85-1.4); 0 — без неё")
    ap.add_argument("--lora-file", default=LORA, help="файл LoRA в models/loras на arrakis")
    ap.add_argument("--gen-size", default="512x512", help="размер генерации; LoRA учили на 512x512")
    ap.add_argument("--bg-tol", type=int, default=60, help="допуск цвета фона при вырезании")
    ap.add_argument("--out", default="art_out", help="куда складывать (относительно game/)")
    ap.add_argument("--bg", choices=["green", "magenta"],
                    help="фон-хромакей; по умолчанию green, для зелёного в описании — magenta")
    ap.add_argument("--raw-prompt", action="store_true", help="не дописывать триггеры и фон к описанию")
    a = ap.parse_args()

    size_default, anchor, framing = KINDS[a.kind]
    size = pixelize.parse_size(a.size) if a.size else size_default
    seed = a.seed if a.seed is not None else random.randrange(2 ** 31)
    bg = a.bg or ("magenta" if any(w in a.description.lower() for w in GREENISH) else "green")
    if a.raw_prompt:
        prompt = a.description
    elif a.ref:
        # Правка: описываем изменение, а стиль и фигуру держит образец.
        prompt = f"{a.description}, pixel art sprite, {BACKGROUNDS[bg]}"
    else:
        prompt = f"pixel art sprite, {a.description}, {framing}, game asset, {BACKGROUNDS[bg]}"
    pal_path = a.palette or (GAME / "assets/palette.hex")
    palette = pixelize.load_palette(pal_path) if Path(pal_path).exists() else None

    out = GAME / a.out / a.name
    out.mkdir(parents=True, exist_ok=True)
    # Godot не должен импортировать черновики: иначе он тащит их в .godot/ и плодит .import.
    (out.parent / ".gdignore").touch()
    ensure_up()
    ref_name = upload(a.ref) if a.ref else None
    graph = build_graph(prompt, seed, max(1, min(8, a.count)), pixelize.parse_size(a.gen_size),
                        a.lora, ref_name, a.lora_file)
    print(f"рисую {a.count} шт., зерно {seed}: {prompt}", file=sys.stderr)
    raws, secs = run_graph(graph)

    previews, files = [], []
    for i, raw in enumerate(raws):
        raw.save(out / f"raw_{i:02d}.png")
        # Приоритет тёмного — только персонажам: их промпт просит упрощённый стиль,
        # и без него пропадают глаза. Предметам он только темнит заливки.
        sprite = pixelize.process(raw, size, palette, a.colors, anchor, a.outline, a.bg_tol,
                                  chroma=bg, dark_share=0.25 if a.kind == "character" else 2.0)
        sprite.save(out / f"sprite_{i:02d}.png")
        files.append(f"sprite_{i:02d}.png")
        previews.append(pixelize.preview(sprite, max(2, 256 // max(size))))
        previews.append(pixelize.preview(raw.resize((256, 256), Image.Resampling.LANCZOS).convert("RGBA"), 1))
    labels = [f"{i:02d}" if k % 2 == 0 else f"raw {i:02d}" for i in range(len(raws)) for k in range(2)]
    pixelize.contact_sheet(previews, labels).save(out / "sheet.png")
    (out / "meta.json").write_text(json.dumps({
        "name": a.name, "description": a.description, "prompt": prompt, "seed": seed,
        "kind": a.kind, "bg": bg, "size": list(size), "count": len(raws), "ref": a.ref,
        "palette": str(pal_path) if palette else None, "colors": None if palette else a.colors,
        "outline": a.outline, "lora_strength": a.lora, "gen_size": a.gen_size, "bg_tol": a.bg_tol,
        "model": {"unet": UNET, "clip": CLIP, "vae": VAE, "lora": a.lora_file, "steps": 4, "cfg": 1.0},
        "seconds": round(secs, 1), "created": time.strftime("%Y-%m-%d %H:%M:%S"),
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"готово за {secs:.0f} с: {out.relative_to(GAME)}/sheet.png  ({', '.join(files)})")


if __name__ == "__main__":
    main()
