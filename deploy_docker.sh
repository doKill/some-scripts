#!/bin/bash

set -e

echo "🚀 开始部署 Drone Runner..."

# === 检查 Docker 是否已安装 ===
if command -v docker &> /dev/null; then
    echo "✅ Docker 已安装，跳过安装步骤。"
else
    echo "📦 未检测到 Docker，开始安装 Docker..."
    apt update -y
    apt install -y ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker
    echo "✅ Docker 安装完成。"
fi
