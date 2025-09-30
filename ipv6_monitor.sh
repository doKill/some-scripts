#!/bin/sh
LOGFILE="/root/ipv6_lease.log"
DATE=$(date "+%Y-%m-%d %H:%M:%S")

# 获取 IPv6 租期信息
LEASE_JSON=$(ifstatus wan6)
PREFERRED=$(echo "$LEASE_JSON" | grep -o '"preferred":[0-9]*' | cut -d: -f2)
VALID=$(echo "$LEASE_JSON" | grep -o '"valid":[0-9]*' | cut -d: -f2)

# 转换为小时/分钟
PREF_MIN=$(($PREFERRED / 60))
VALID_HOUR=$(($VALID / 3600))

# 写入日志
echo "$DATE | Preferred: $PREFERRED s (~${PREF_MIN} min), Valid: $VALID s (~${VALID_HOUR} h)" >> $LOGFILE

# 检查 preferred 是否快过期
if [ $PREFERRED -lt 600 ]; then
    echo "$DATE ⚠️ Preferred 剩余不足10分钟，疑似续租失败！尝试重启 wan6..." >> $LOGFILE

    # 重启 WAN6 接口
    ifup wan6
    sleep 10  # 等待 10 秒
    # 再检查一次
    NEW_JSON=$(ifstatus wan6)
    NEW_PREF=$(echo "$NEW_JSON" | grep -o '"preferred":[0-9]*' | cut -d: -f2)
    NEW_VALID=$(echo "$NEW_JSON" | grep -o '"valid":[0-9]*' | cut -d: -f2)

    if [ "$NEW_PREF" -gt "$PREFERRED" ]; then
        echo "$DATE ✅ WAN6 重启成功，租期已刷新 (Preferred=$NEW_PREF, Valid=$NEW_VALID)" >> $LOGFILE
    else
        echo "$DATE ❌ WAN6 重启失败，租期未刷新" >> $LOGFILE
    fi
fi
