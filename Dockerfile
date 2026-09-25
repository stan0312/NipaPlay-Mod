# ---------- 构建阶段：Flutter Web ----------
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app

# 复制全部源码（包括本地路径依赖 third_party/）
COPY . .

RUN flutter pub get

# 构建 Web 版
RUN flutter build web --release --base-href /

# ---------- 运行阶段：Nginx ----------
FROM nginx:alpine

# 复制 Nginx 配置
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# 复制构建产物
COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
