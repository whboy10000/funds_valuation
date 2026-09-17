# 将本地 ./build/web 产物打包为可运行容器。
#
# 本地使用：
#   flutter build web --release
#   docker build -t fund-valuation .
#   docker run -d -p 8080:80 fund-valuation
#
# CI 中由 .github/workflows/release.yml 构建并推送到 ghcr.io。
FROM nginx:alpine

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY build/web /usr/share/nginx/html

EXPOSE 80
