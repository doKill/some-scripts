#!/bin/bash

# 设置远程配置文件的URL
REMOTE_URL="https://raw.githubusercontent.com/v2fly/domain-list-community/master/data/netflix"
LOCAL_FILE="/etc/dnsmasq.conf"

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

# 解析远程文件并生成所需配置
echo "正在解析远程配置并更新本地文件..."
while IFS= read -r line; do
  # 跳过注释、空行，以及非普通域名行
  if [[ "$line" =~ ^#.* ]] || [[ -z "$line" ]] || [[ "$line" =~ ^regexp: ]] || [[ "$line" =~ ^full: ]]; then
    continue
  fi

  # 如果是普通域名行或以 # DNS test 开头，生成对应的 dnsmasq 配置
  if [[ "$line" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || [[ "$line" == "# DNS test" ]]; then
    # 如果是注释行，保留原样
    if [[ "$line" == "# DNS test" ]]; then
      OUTPUT_LINE="$line"
    else
      OUTPUT_LINE="server=/$line/#"$'\n'"address=/$line/::"
    fi

    # 检查是否已存在于本地文件中，避免重复
    if ! grep -Fqx "$OUTPUT_LINE" "$LOCAL_FILE"; then
      echo "$OUTPUT_LINE" >> "$LOCAL_FILE"
    fi
  fi
done < "$TEMP_FILE"

# 删除临时文件
rm -f "$TEMP_FILE"

# 重启dnsmasq服务
echo "重新启动dnsmasq服务..."
/etc/init.d/dnsmasq restart

echo "配置更新完成。"
