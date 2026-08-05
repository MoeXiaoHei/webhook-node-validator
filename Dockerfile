FROM python:3.9-slim

# 安装依赖
RUN pip install --no-cache-dir flask gunicorn

# 创建工作目录
WORKDIR /app

# 启动命令
CMD ["gunicorn", "--bind", "0.0.0.0:8443", "--certfile=/app/certs/tls.crt", "--keyfile=/app/certs/tls.key", "--workers=2", "--threads=4", "--access-logfile=-", "--error-logfile=-", "--log-level=info", "webhook:app"]
