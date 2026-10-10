#!/bin/sh

AUTH_SERVER="http://10.80.80.249"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
CACHE_FILE="/tmp/zjkju-auth-last-url"

. /lib/functions.sh

logger -t zjkju-auth "wrapper started"

is_online() {
    for PING_TARGET in 223.5.5.5 223.6.6.6; do
        if ping -c 1 -W 2 "$PING_TARGET" >/dev/null 2>&1; then
            return 0
        fi
    done
    BODY=$(curl -s --max-time 5 -A "$UA" \
        "http://www.msftconnecttest.com/connecttest.txt" 2>/dev/null | tr -d '\r\n')
    [ "$BODY" = "Microsoft Connect Test" ]
}

# ============================================================
# 抓取认证页 URL：访问多个外网地址，从 302 Location 提取
# 网关未拦截时返回空，由主循环静默重试
# ============================================================
fetch_auth_url() {
    config_get manual_url main manual_url
    if [ -n "$manual_url" ]; then
        echo "$manual_url"
        return 0
    fi

    for TRIGGER in \
        "http://www.baidu.com/" \
        "http://www.qq.com/" \
        "http://www.example.com/" \
        "http://www.qualcomm.com/" \
        "http://www.neverssl.com/"; do

        RAW=$(curl -s -i --max-time 5 -A "$UA" "$TRIGGER" 2>/dev/null)

        # Location 头
        LOC=$(echo "$RAW" | grep -i '^Location:' | head -1 \
            | sed 's/^[Ll]ocation: *//' | tr -d '\r\n')
        case "$LOC" in
            *wlanuserip=*) echo "$LOC"; return 0 ;;
        esac

        # body 里的完整 URL
        EXT=$(echo "$RAW" | grep -oE "http[s]?://[^\"'<> ]*wlanuserip=[^\"'<> ]*" | head -1)
        if [ -n "$EXT" ]; then
            echo "$EXT"
            return 0
        fi

        # body 里的相对路径
        EXT=$(echo "$RAW" | grep -oE "/eportal/index\.jsp\?[^\"'<> ]+" | head -1)
        if [ -n "$EXT" ]; then
            echo "$AUTH_SERVER$EXT"
            return 0
        fi
    done

    # 缓存兜底
    if [ -f "$CACHE_FILE" ]; then
        CACHED=$(cat "$CACHE_FILE" 2>/dev/null)
        if echo "$CACHED" | grep -q "wlanuserip="; then
            echo "$CACHED"
            return 0
        fi
    fi

    return 1
}

urlencode_query() {
    echo "$1" | sed 's/=/\%3D/g; s/&/\%26/g'
}

do_auth() {
    AUTH_URL="$1"
    USERNAME="$2"
    PASSWORD="$3"
    SERVICE="$4"

    QUERY_STRING="${AUTH_URL#*\?}"
    if [ "$QUERY_STRING" = "$AUTH_URL" ]; then
        logger -t zjkju-auth "URL 无效，跳过"
        return 1
    fi

    QS_ENCODED=$(urlencode_query "$QUERY_STRING")

    logger -t zjkju-auth "锐捷认证客户端启动"
    logger -t zjkju-auth "用户名: $USERNAME"
    logger -t zjkju-auth "认证地址: $AUTH_URL"
    logger -t zjkju-auth "提取到queryString (长度: ${#QUERY_STRING})"

    RESPONSE=$(curl -s --max-time 10 -X POST \
        "$AUTH_SERVER/eportal/InterFace.do?method=login" \
        -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
        -H "User-Agent: $UA" \
        -H "Referer: $AUTH_URL" \
        -H "Origin: $AUTH_SERVER" \
        --data-urlencode "userId=$USERNAME" \
        --data-urlencode "password=$PASSWORD" \
        --data-urlencode "service=$SERVICE" \
        --data-urlencode "queryString=$QS_ENCODED" \
        --data-urlencode "operatorPwd=" \
        --data-urlencode "operatorUserId=" \
        --data-urlencode "validcode=" \
        --data-urlencode "passwordEncrypt=false" \
        2>&1)

    logger -t zjkju-auth "响应内容: $(echo "$RESPONSE" | head -c 300)"

    case "$RESPONSE" in
        *'"result":"success"'*)
            logger -t zjkju-auth "认证成功！"
            return 0
            ;;
        *'"result":"fail"'*)
            MSG=$(echo "$RESPONSE" | grep -oE '"message":"[^"]+"' | head -1)
            logger -t zjkju-auth "认证失败: $MSG"
            return 1
            ;;
        *)
            logger -t zjkju-auth "认证请求已提交"
            return 1
            ;;
    esac
}

# ============================================================
# 主循环
# ============================================================
while true; do
    config_load zjkju-auth

    config_get_bool enabled main enabled 1
    config_get username main username
    config_get password main password
    config_get service main service
    config_get check_interval main check_interval 5

    if [ "$enabled" != "1" ]; then
        sleep 10
        continue
    fi

    if [ -z "$username" ] || [ -z "$password" ]; then
        logger -t zjkju-auth "未配置学号/密码，等待用户在 LuCI 界面填写"
        sleep 30
        continue
    fi

    # 在线时静默等待
    if is_online; then
        sleep "$check_interval"
        continue
    fi

    # 掉线了，尝试抓 URL
    AUTH_URL=$(fetch_auth_url)
    if [ -z "$AUTH_URL" ]; then
        # ★ 关键：抓不到 URL 时不报错，静默重试
        # 网关有 2-3 分钟的观察期，这段时间抓不到是正常的
        sleep 5
        continue
    fi

    # 抓到了 URL，立即认证
    logger -t zjkju-auth "检测到掉线，开始认证"
    if do_auth "$AUTH_URL" "$username" "$password" "$service"; then
        case "$AUTH_URL" in
            *wlanuserip=*)
                echo "$AUTH_URL" > "$CACHE_FILE"
                ;;
        esac
    fi

    sleep "$check_interval"
done
