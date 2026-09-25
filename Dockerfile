# ---------- 构建阶段：Flutter Web ----------
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app

# 复制依赖文件
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# 复制全部源码
COPY . .

# 构建 Web 版（renderer=canvaskit，体积小、兼容性好）
RUN flutter build web --release --base-href /

# ---------- 运行阶段：Nginx ----------
FROM nginx:alpine

# 复制 Nginx 配置
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# 复制构建产物
COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
