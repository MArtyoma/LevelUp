#!/usr/bin/env python3
"""Чинит LoRA Limbicnation/pixel-art-lora под ComfyUI (запускается внутри контейнера comfy).

В файле `pytorch_lora_weights.comfyui.safetensors` 6 ключей глобальной модуляции
названы по-diffusers (`double_stream_modulation_img.linear`), а в ComfyUI слой
называется `...modulation_img.lin`. ComfyUI такие ключи пропускает с предупреждением
«lora key not loaded», и LoRA работает не полностью: без модуляции стиль слабее
(проверено 25.09.2026 на одном зерне, docs/art-pipeline.md). Переименовываем их в
общий формат ComfyUI `diffusion_model.<имя слоя>`; остальные 166 ключей не трогаем.

  comfy /opt/venv/bin/python fix_lora.py SRC DST
"""
import sys

from safetensors.torch import load_file, save_file

src, dst = sys.argv[1], sys.argv[2]
sd = load_file(src)
out, n = {}, 0
for k, v in sd.items():
    if "_modulation" in k and ".linear." in k:
        k = "diffusion_model." + k.replace(".linear.", ".lin.")
        n += 1
    out[k] = v
save_file(out, dst, metadata={"note": "Limbicnation/pixel-art-lora, modulation keys renamed for ComfyUI"})
print(f"переименовано {n} ключей из {len(sd)}")
