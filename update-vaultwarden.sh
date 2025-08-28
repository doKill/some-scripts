#!/bin/bash
set -e

CONTAINER_NAME="vaultwarden"
IMAGE_NAME="vaultwarden/server:latest"
DATA_DIR="/vw-data"
PORT=8012

echo "=== 更新 Vaultwarden 开始 ==="

# 拉取最新镜像
echo "[1/5] 拉取最新镜像..."
docker pull $IMAGE_NAME

# 停止并删除旧容器
if [ "$(docker ps -aq -f name=$CONTAINER_NAME)" ]; then
  echo "[2/5] 停止并删除旧容器..."
  docker stop $CONTAINER_NAME || true
  docker rm $CONTAINER_NAME || true
fi

# 启动新容器
echo "[3/5] 启动新容器..."
docker run -d --name $CONTAINER_NAME \
  -v $DATA_DIR:/data \
  -p $PORT:80 \
  $IMAGE_NAME

# 清理无用镜像
echo "[4/5] 清理无用镜像..."
docker image prune -f

# 健康检查
echo "[5/5] 健康检查..."
sleep 5   # 等容器初始化几秒
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT)

if [ "$STATUS_CODE" = "200" ]; then
  echo "✅ Vaultwarden 正常运行 (HTTP 200)"
else
  echo "⚠️ Vaultwarden 可能异常，返回状态码: $STATUS_CODE"
fi

echo "=== 更新完成 ==="
docker ps --filter "name=$CONTAINER_NAME"

# 每周日凌晨 5 点执行更新  0 5 * * * curl -fsSL https://raw.githubusercontent.com/doKill/some-scripts/master/update-vaultwarden.sh | bash >> /root/update-vaultwarden.log 2>&1
