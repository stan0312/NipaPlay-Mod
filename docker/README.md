# NipaPlay Web Docker 部署

## 构建

```bash
docker build -t nipaplay-web .
```

## 运行

```bash
docker run -d --name nipaplay-web -p 8080:80 nipaplay-web
```

浏览器打开 http://localhost:8080

## 说明

- 基于 Flutter Web (canvaskit renderer) 编译，桌面/移动端浏览器都能用
- Nginx 托管静态文件，支持 SPA 路由
- 首次打开会加载 flutter web 引擎（约几 MB），之后有缓存
- Emby 服务器地址在 App 设置里填，和 iOS 版一样
