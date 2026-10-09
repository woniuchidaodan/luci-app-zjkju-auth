#!/bin/sh

RUJIE=/usr/bin/ruijie
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
CACHE_FILE="/tmp/zjkju-auth-last-url"
OUT_FILE="/tmp/zjkju-auth-out.log"

. /lib/functions.sh

logger -t zjkju-auth "wrapper started"

# 检查是否启用：未启用直接退出
config_load zjkju-auth
config_get_bool enabled main enabled 0
if [ "$enabled" != "1" ]; then
    logger -t zjkju-auth "服务未启用，wrapper 退出"
    exit 0
fi

is_online() {
    BODY=$(curl -s --max-time 5 -A "$UA" \
        "http://www.msftconnecttest.com/connecttest.txt" 2>/dev/null | tr -d '\r\n')
    [ "$BODY" = "Microsoft Connect Test" ]
}

fetch_auth_url() {
    config_get manual_url main manual_url
    if [ -n "$manual_url" ]; then
        echo "$manual_url"
        return 0
    fi

    for TRIGGER in \
        "http://www.baidu.com/" \
        "http://www.example.com/" \
        "http://www.qualcomm.com/" \
        "http://neverssl.com/" \
        "http://www.qq.com/"; do

        RAW=$(curl -s -i --max-time 5 -A "$UA" "$TRIGGER" 2>/dev/null)

        LOC=$(echo "$RAW" | grep -i '^Location:' | head -1 \
            | sed 's/^[Ll]ocation: *//' | tr -d '\r\n')
        case "$LOC" in
            *wlanuserip=*) echo "$LOC"; return 0 ;;
        esac

        EXT=$(echo "$RAW" | grep -oE "http[s]?://[^\"'<> ]*wlanuserip=[^\"'<> ]*" | head -1)
        if [ -n "$EXT" ]; then
            echo "$EXT"
            return 0
        fi

        EXT=$(echo "$RAW" | grep -oE "/eportal/index\.jsp\?[^\"'<> ]+" | head -1)
        if [ -n "$EXT" ]; then
            echo "http://10.80.80.249$EXT"
            return 0
        fi
    done

    if [ -f "$CACHE_FILE" ]; then
        CACHED=$(cat "$CACHE_FILE" 2>/dev/null)
        if echo "$CACHED" | grep -q "wlanuserip="; then
            echo "$CACHED"
            return 0
        fi
    fi

    return 1
}

while true; do
    config_load zjkju-auth

    config_get_bool enabled main enabled 0
    config_get username main username
    config_get password main password
    config_get service main service
    config_get check_interval main check_interval 60

    # 用户取消勾选后，wrapper 优雅退出
    if [ "$enabled" != "1" ]; then
        logger -t zjkju-auth "服务已禁用，wrapper 退出"
        exit 0
    fi

    if [ -z "$username" ] || [ -z "$password" ]; then
        logger -t zjkju-auth "未配置学号/密码，等待用户在 LuCI 界面填写"
        sleep 30
        continue
    fi

    if is_online; then
        sleep "$check_interval"
        continue
    fi

    logger -t zjkju-auth "检测到掉线，开始认证"

    AUTH_URL=$(fetch_auth_url)
    if [ -z "$AUTH_URL" ]; then
        AUTH_URL="http://10.80.80.249/eportal/index.jsp"
    fi

    $RUJIE -u "$username" -p "$password" -s "$service" -m "$AUTH_URL" > "$OUT_FILE" 2>&1

    if [ -f "$OUT_FILE" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] && logger -t zjkju-auth "$line"
        done < "$OUT_FILE"
    fi

    if grep -q "认证成功" "$OUT_FILE" 2>/dev/null; then
        case "$AUTH_URL" in
            *wlanuserip=*)
                echo "$AUTH_URL" > "$CACHE_FILE"
                ;;
        esac
    fi

    sleep "$check_interval"
done
