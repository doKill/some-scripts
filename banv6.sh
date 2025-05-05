#!/bin/bash

# 配置远程 URL
URLS=(
  # "https://raw.githubusercontent.com/v2fly/domain-list-community/master/data/netflix"
  "https://raw.githubusercontent.com/v2fly/domain-list-community/master/data/openai"
)
LOCAL_FILE="/etc/dnsmasq.conf"

# 临时文件存储下载内容
TEMP_FILE=$(mktemp)

# 确保本地文件存在
if [ ! -f "$LOCAL_FILE" ]; then
  touch "$LOCAL_FILE"
fi

# 下载并解析每个 URL 的内容
echo "正在下载和解析远程配置..."
for URL in "${URLS[@]}"; do
  wget -q -O - "$URL" | \
  # 过滤保留的域名部分
  grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$|^# Main domain|^# DNS test" | \
  # 跳过注释和空行
  awk '!/^#/ && NF {print}' | \
  # 删除重复行
  sort -u >> "$TEMP_FILE"
done

# 生成 dnsmasq 配置
echo "正在更新本地配置文件..."
while IFS= read -r line; do
  # 跳过注释行
  if [[ "$line" =~ ^#.* ]]; then
    echo "$line" >> "$LOCAL_FILE"
    continue
  fi

  # 生成 `server=` 和 `address=` 配置
  OUTPUT_LINE="server=/$line/#"$'\n'"address=/$line/::"

  # 检查是否已存在于本地文件中，避免重复
  if ! grep -Fqx "$OUTPUT_LINE" "$LOCAL_FILE"; then
    echo "$OUTPUT_LINE" >> "$LOCAL_FILE"
  fi
done < "$TEMP_FILE"

# 删除临时文件
rm -f "$TEMP_FILE"

# 重启 dnsmasq 服务
echo "重新启动 dnsmasq 服务..."
/etc/init.d/dnsmasq restart

echo "配置更新完成。"
