# 基于 n8n 官方镜像，补装 p7zip 以支撑「备份-CSV导出-7z压缩-邮件」工作流
FROM n8nio/n8n:latest
USER root
# n8n 官方镜像基于 Alpine，用 apk 安装 p7zip（提供 7z 命令）
RUN apk add --no-cache p7zip
# 若你的 n8n 镜像基于 Debian（apt 而非 apk），改用下面这一行并删除上一行：
# RUN apt-get update && apt-get install -y p7zip-full && rm -rf /var/lib/apt/lists/*
USER node
