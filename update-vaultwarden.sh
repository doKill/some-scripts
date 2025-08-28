#!/bin/bash
set -e

CONTAINER_NAME="vaultwarden"
IMAGE_NAME="vaultwarden/server:latest"
DATA_DIR="/vw-data"

echo "=== 更新 Vaultwarden 开始 ==="

# 拉取最新镜像
echo "[1/4] 拉取最新镜像..."
docker pull $IMAGE_NAME

# 停止并删除旧容器
if [ "$(docker ps -aq -f name=$CONTAINER_NAME)" ]; then
  echo "[2/4] 停止并删除旧容器..."
  docker stop $CONTAINER_NAME || true
  docker rm $CONTAINER_NAME || true
fi

# 启动新容器（注意端口映射 8012:80）
echo "[3/4] 启动新容器..."
docker run -d --name $CONTAINER_NAME \
  -v $DATA_DIR:/data \
  -p 8012:80 \
  $IMAGE_NAME

# 清理无用镜像
echo "[4/4] 清理无用镜像..."
docker image prune -f

echo "=== 更新完成 ==="
docker ps --filter "name=$CONTAINER_NAME"
