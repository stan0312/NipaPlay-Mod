# NipaPlay Web 版 Dockerfile（NAS 部署版）
# 直接使用 GitHub Actions 构建好的 web 静态文件，无需在 NAS 上安装 Flutter

FROM nginx:alpine

# 删除默认 nginx 配置
RUN rm /etc/nginx/conf.d/default.conf

# 复制自定义 nginx 配置（支持 SPA 路由）
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# 复制 Flutter web 构建产物（Actions 下载的 zip 解压后的 web 目录内容）
COPY web/ /usr/share/nginx/html/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
