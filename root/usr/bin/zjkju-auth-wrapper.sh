#!/bin/sh

AUTH_SERVER="http://10.80.80.249"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
CACHE_FILE="/tmp/zjkju-auth-last-url"

. /lib/functions.sh

logger -t zjkju-auth "wrapper started"

# ============================================================
# 在线检测：先 ping（双 DNS 兜底），失败再 HTTP（方案 C）
# ============================================================
is_online() {
    # 第 1 层：ping 阿里双 DNS（主 + 备）
    for PING_TARGET in 223.5.5.5 223.6.6.6; do
        if ping -c 1 -W 2 "$PING_TARGET" >/dev/null 2>&1; then
            return 0
        fi
    done

    # 第 2 层：ping 都失败（ICMP 被拦 或 真掉线），用 HTTP 确认
    BODY=$(curl -s --max-time 5 -A "$UA" \
        "http://www.msftconnecttest.com/connecttest.txt" 2>/dev/null | tr -d '\r\n')
    [ "$BODY" = "Microsoft Connect Test" ]
}

# ============================================================
# 抓取认证页 URL（三层兜底）
# ============================================================
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
        "http://www.neverssl.com/" \
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
            echo "$AUTH_SERVER$EXT"
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
        logger -t zjkju-auth "未能从URL中提取queryString"
        logger -t zjkju-auth "请确保URL包含 wlanuserip 等参数"
        return 1
    fi

    QS_ENCODED=$(urlencode_query "$QUERY_STRING")

    logger -t zjkju-auth "锐捷认证客户端启动"
    logger -t zjkju-auth "用户名: $USERNAME"
    logger -t zjkju-auth "身份类型: $SERVICE"
    logger -t zjkju-auth "使用手动指定的认证地址"
    logger -t zjkju-auth "认证地址: $AUTH_URL"
    logger -t zjkju-auth "提取到queryString (长度: ${#QUERY_STRING})"
    logger -t zjkju-auth "认证请求URL: $AUTH_SERVER/eportal/InterFace.do?method=login"
    logger -t zjkju-auth "发送POST数据..."

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

    logger -t zjkju-auth "响应状态: 200"
    logger -t zjkju-auth "响应内容: $(echo "$RESPONSE" | head -c 500)"

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
            logger -t zjkju-auth "认证请求已提交，请检查是否能正常上网"
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
    config_get check_interval main check_interval 10

    if [ "$enabled" != "1" ]; then
        sleep 10
        continue
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
        AUTH_URL="$AUTH_SERVER/eportal/index.jsp"
    fi

    if do_auth "$AUTH_URL" "$username" "$password" "$service"; then
        case "$AUTH_URL" in
            *wlanuserip=*)
                echo "$AUTH_URL" > "$CACHE_FILE"
                ;;
        esac
    fi

    sleep "$check_interval"
done
