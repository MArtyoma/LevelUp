#!/bin/bash
# Установка моделей звука и музыки на arrakis (ComfyUI, каталог /srv/models/comfy).
#
# Запуск на arrakis от root:  bash install_arrakis.sh
# Повторный запуск безопасен: готовое с верной суммой пропускается, обрыв докачивается.
#
# Что ставится (~33 ГБ):
#   Stable Audio 3 (Stability AI, май 2026; Stability Community License — бесплатно
#   при выручке < $1 млн). Перепаковка Comfy-Org: без гейта HF, сразу под ComfyUI.
#     checkpoints/stable_audio_3_small_sfx.safetensors     2.2 ГБ  звуки: шаги, двери, техника
#     checkpoints/stable_audio_3_medium.safetensors        8.8 ГБ  музыка, эмбиент, до 6 мин
#     text_encoders/t5gemma_b_b_ul2.safetensors            1.1 ГБ  общий энкодер обеих
#   MiniMax Music 3 (MiniMax, авг. 2026; Apache 2.0 на перепаковке Comfy-Org) — песни и
#   инструментал до 5 мин. Требует ComfyUI >= 0.33 (у нас сборка v0.37.0, см.
#   /srv/projects/vault/host/comfyui.Containerfile).
#     diffusion_models/minimax_music3_dit_fp16.safetensors 4.7 ГБ
#     text_encoders/minimax_music3_text_encoder_pruned_bf16.safetensors 15.9 ГБ
#     vae/minimax_music3_dav.safetensors                   0.2 ГБ
#   Энкодер MiniMax берём bf16, а не int8: int8 «convrot» на ROCm не проверен,
#   а память на машине есть (ComfyUI доступно ~46 ГиБ рядом с языковой моделью).
#   ACE-Step 1.5 уже стоит (checkpoints/ace_step_1.5_turbo_aio.safetensors).
set -euo pipefail

ROOT=${COMFY_MODELS:-/srv/models/comfy}
HF=https://huggingface.co
SA=$HF/Comfy-Org/stable-audio-3/resolve/main
MM=$HF/Comfy-Org/MiniMax-Music-3/resolve/main

# путь_в_ROOT  URL  sha256
FILES=(
  "checkpoints/stable_audio_3_small_sfx.safetensors
   $SA/checkpoints/stable_audio_3_small_sfx.safetensors
   ed9cf1b6172f1a8c2921a9560c21109ff3239524563ced9dce6dcdef41e2f515"
  "text_encoders/t5gemma_b_b_ul2.safetensors
   $SA/text_encoders/t5gemma_b_b_ul2.safetensors
   1e1eba25be8872edb0d3c6335c6658fd6388e7b14b60da6e454e404cfcd8150e"
  "checkpoints/stable_audio_3_medium.safetensors
   $SA/checkpoints/stable_audio_3_medium.safetensors
   48d9c65e290e7bcd5194e0633bfc2424a59ee9683f5c2d58762d997b7d8ce0b5"
  "vae/minimax_music3_dav.safetensors
   $MM/vae/minimax_music3_dav.safetensors
   2a32155b769be01445fcc2a8663b910fc9e1751e18dc1c3ec528064512d9ef0c"
  "diffusion_models/minimax_music3_dit_fp16.safetensors
   $MM/diffusion_models/minimax_music3_dit_fp16.safetensors
   45494a2b6b69af115902ff28eaf54118d19067aa54da01000f3e3efce7ba0e34"
  "text_encoders/minimax_music3_text_encoder_pruned_bf16.safetensors
   $MM/text_encoders/minimax_music3_text_encoder_pruned_bf16.safetensors
   e81e469c92af324dc69b77e5a11179e22542a6d628f2b205c8cf6143e510d976"
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
chown worker:worker "$ROOT"/{checkpoints,diffusion_models,text_encoders,vae}/*.safetensors
echo "готово"
