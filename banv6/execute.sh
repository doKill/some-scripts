#!/bin/bash

# 设置远程配置文件的URL
REMOTE_URL="https://raw.githubusercontent.com/doKill/some-scripts/master/banv6/list.conf"
LOCAL_FILE="/etc/dnsmasq.conf"

# 获取配置文件的修改时间
config_mtime=$(stat -c %Y "$REMOTE_URL")

# 下载远程配置到临时文件
TEMP_FILE=$(mktemp)
wget -q -O "$TEMP_FILE" "$REMOTE_URL"

if [ $? -ne 0 ]; then
  echo "无法下载远程配置文件，请检查URL是否正确。"
  exit 1
fi

# 确保本地文件存在
if [ ! -f "$LOCAL_FILE" ]; then
  touch "$LOCAL_FILE"
fi

# 解析并合并配置
echo "正在更新配置文件..."
while IFS= read -r line; do
  # 跳过注释和空行
  if [[ "$line" =~ ^#.* ]] || [[ -z "$line" ]]; then
    continue
  fi

  # 如果本地文件中没有该条目，添加到本地文件
  if ! grep -Fxq "$line" "$LOCAL_FILE"; then
    echo "$line" >> "$LOCAL_FILE"
  fi
done < "$TEMP_FILE"

# 删除临时文件
rm -f "$TEMP_FILE"

# 重启dnsmasq服务
echo "重新启动dnsmasq服务..."
/etc/init.d/dnsmasq restart

echo "配置更新完成。"
