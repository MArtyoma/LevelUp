#!/usr/bin/env bash
# Добавляет запись в журнал команды за сегодня: journal/ГГГГ-ММ-ДД.md
# Использование: ./tools/log.sh "Имя" "тема" "текст записи"
set -euo pipefail

if [ "$#" -lt 3 ]; then
    echo "Использование: $0 \"Имя\" \"тема\" \"текст записи\"" >&2
    echo "Пример: $0 \"Саша\" \"[затык] TileMap\" \"Не понимаю слой коллизий, сижу второй час\"" >&2
    exit 1
fi

AUTHOR="$1"
TOPIC="$2"
shift 2
BODY="$*"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/journal"
mkdir -p "$DIR"

DAY="$(date '+%Y-%m-%d')"
TIME="$(date '+%H:%M')"
FILE="$DIR/$DAY.md"

if [ ! -f "$FILE" ]; then
    case "$(date '+%u')" in
        1) WD="понедельник" ;; 2) WD="вторник"     ;; 3) WD="среда"   ;;
        4) WD="четверг"     ;; 5) WD="пятница"     ;; 6) WD="суббота" ;;
        *) WD="воскресенье" ;;
    esac
    printf '# %s, %s\n\n' "$(date '+%d.%m.%Y')" "$WD" > "$FILE"
fi

printf '### %s — %s — %s\n%s\n\n' "$TIME" "$AUTHOR" "$TOPIC" "$BODY" >> "$FILE"
echo "journal/$DAY.md ← $TIME — $AUTHOR — $TOPIC"
