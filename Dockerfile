# NipaPlay Web 版 Dockerfile
# 多阶段构建：第一阶段用 Flutter SDK 编译 web，第二阶段用 nginx 托管静态文件

# ===== 阶段 1：Flutter Web 构建 =====
FROM ghcr.io/fluttertools/flutter:stable AS builder

WORKDIR /app

# 复制 pubspec 并先拉依赖（利用 Docker 缓存层）
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# 复制剩余源码
COPY . .

# 构建 web release（ renderer=canvaskit 兼容性最好，base-href=/ ）
RUN flutter build web --release --web-renderer canvaskit --base-href /

# ===== 阶段 2：Nginx 托管 =====
FROM nginx:alpine

# 删除默认 nginx 配置
RUN rm /etc/nginx/conf.d/default.conf

# 复制自定义 nginx 配置（支持 SPA 路由）
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# 复制 Flutter web 构建产物
COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
