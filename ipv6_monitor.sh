#!/bin/sh
LOGFILE="/root/ipv6_lease.log"
DATE=$(date "+%Y-%m-%d %H:%M:%S")

LEASE_JSON=$(ifstatus wan6)
PREFERRED=$(echo "$LEASE_JSON" | grep -o '"preferred":[0-9]*' | cut -d: -f2)
VALID=$(echo "$LEASE_JSON" | grep -o '"valid":[0-9]*' | cut -d: -f2)

# 避免空值报错
[ -z "$PREFERRED" ] && PREFERRED=0
[ -z "$VALID" ] && VALID=0

# 转换
PREF_MIN=$(expr $PREFERRED / 60)
VALID_HOUR=$(expr $VALID / 3600)

echo "$DATE | Preferred: $PREFERRED s (~${PREF_MIN} min), Valid: $VALID s (~${VALID_HOUR} h)" >> $LOGFILE

if [ "$PREFERRED" -lt 600 ]; then
    echo "$DATE ⚠️ Preferred 剩余不足10分钟，疑似续租失败！尝试重启 wan6..." >> $LOGFILE
    ifup wan6
    sleep 10
    NEW_JSON=$(ifstatus wan6)
    NEW_PREF=$(echo "$NEW_JSON" | grep -o '"preferred":[0-9]*' | cut -d: -f2)
    [ -z "$NEW_PREF" ] && NEW_PREF=0
    if [ "$NEW_PREF" -gt "$PREFERRED" ]; then
        echo "$DATE ✅ WAN6 重启成功，租期已刷新 (Preferred=$NEW_PREF)" >> $LOGFILE
    else
        echo "$DATE ❌ WAN6 重启失败，租期未刷新" >> $LOGFILE
    fi
fi
