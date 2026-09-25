#!/bin/bash
# Установка генератора спрайтов на arrakis: FLUX.2 [klein] 4B + пиксельная LoRA.
#
# Запуск на arrakis от root (файлы сами отдаются пользователю worker), рядом
# должен лежать fix_lora.py:
#   scp tools/art/install_arrakis.sh tools/art/fix_lora.py root@192.168.1.202:/srv/work/
#   ssh root@192.168.1.202 bash /srv/work/install_arrakis.sh
# Повторный запуск безопасен: готовые файлы с верной суммой пропускаются,
# недокачанные докачиваются (curl -C -).
#
# Что ставится (~16.5 ГБ) и куда (каталог ComfyUI на arrakis — /srv/models/comfy):
#   diffusion_models/flux-2-klein-4b.safetensors        7.75 ГБ  bf16, дистиллят на 4 шага
#   text_encoders/qwen_3_4b.safetensors                 8.04 ГБ  текстовый энкодер klein
#   vae/flux2-vae.safetensors                           0.34 ГБ
#   loras/pixel-art-sprite-klein4b.safetensors          0.31 ГБ  Limbicnation/pixel-art-lora
#   loras/pixel-art-sprite-klein4b-fixed.safetensors    0.31 ГБ  она же с исправленными
#                                                                ключами (fix_lora.py) — её и берём
#
# Почему bf16, а не fp8. У gfx1151 нет аппаратного fp8: ComfyUI распаковывал бы
# веса в bf16 на каждом шаге. Памяти на машине хватает, скорость дороже.
# Лицензии: klein 4B и LoRA — Apache 2.0, данные LoRA — CC0.
set -euo pipefail

ROOT=${COMFY_MODELS:-/srv/models/comfy}
HF=https://huggingface.co

# путь_в_ROOT  URL  sha256
FILES=(
  "diffusion_models/flux-2-klein-4b.safetensors
   $HF/Comfy-Org/flux2-klein-4B/resolve/main/split_files/diffusion_models/flux-2-klein-4b.safetensors
   ec3d4e733a771f61c052fb4856c48b336c55eaf2c65487c2a1faeb9bbda7a343"
  "text_encoders/qwen_3_4b.safetensors
   $HF/Comfy-Org/flux2-klein-4B/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors
   6c671498573ac2f7a5501502ccce8d2b08ea6ca2f661c458e708f36b36edfc5a"
  "vae/flux2-vae.safetensors
   $HF/Comfy-Org/flux2-klein-4B/resolve/main/split_files/vae/flux2-vae.safetensors
   868fe7b343cc8f3a19dbcfcafbc3d5f888802be3f89bd81b65b3621a066ce8f3"
  "loras/pixel-art-sprite-klein4b.safetensors
   $HF/Limbicnation/pixel-art-lora/resolve/main/pytorch_lora_weights.comfyui.safetensors
   24e938f510f5dd0c890ac8b1078f4abb87a50c9c053b2e85c44821c0f30011ad"
)

for entry in "${FILES[@]}"; do
  read -r rel url sum <<<"$(echo $entry)"
  dst="$ROOT/$rel"
  if [ -f "$dst" ] && sha256sum "$dst" | grep -q "^$sum"; then
    echo "есть: $rel"; continue
  fi
  echo "качаю: $rel"
  # Первый мегабайт — запросом с диапазоном. Полный GET большого файла CDN Hugging Face
  # (xet) может держать минутами без единого байта; с Range отдаёт сразу. Дальше
  # -C - сам шлёт Range, потому что .part уже не пустой.
  [ -s "$dst.part" ] || curl -fsL --http1.1 --retry 10 --retry-all-errors -r 0-1048575 -o "$dst.part" "$url"
  curl -fL --http1.1 --retry 50 --retry-all-errors --retry-delay 5 --speed-limit 500000 --speed-time 30 -C - -o "$dst.part" "$url"
  if ! sha256sum "$dst.part" | grep -q "^$sum"; then
    echo "НЕ СОШЛАСЬ СУММА: $rel — файл оставлен как $dst.part" >&2; exit 1
  fi
  mv "$dst.part" "$dst"
done
chown worker:worker "$ROOT"/{diffusion_models,text_encoders,vae,loras}/*.safetensors

# LoRA с ключами, которые ComfyUI понимает целиком (см. fix_lora.py).
FIXED="$ROOT/loras/pixel-art-sprite-klein4b-fixed.safetensors"
if [ ! -f "$FIXED" ]; then
  here=$(cd "$(dirname "$0")" && pwd)
  install -m 644 "$here/fix_lora.py" "$ROOT/loras/.fix_lora.py"
  (cd /srv && comfy /opt/venv/bin/python /root/comfy-models/loras/.fix_lora.py \
      /root/comfy-models/loras/pixel-art-sprite-klein4b.safetensors \
      /root/comfy-models/loras/pixel-art-sprite-klein4b-fixed.safetensors)
  rm -f "$ROOT/loras/.fix_lora.py"
  chmod 644 "$FIXED"
fi
echo "готово"
