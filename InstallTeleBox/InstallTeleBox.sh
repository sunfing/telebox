#!/bin/bash
# =====================================================
# TeleBox 一键安装脚本 for Debian / Ubuntu (root 用户)
# 说明: 自动完成 TeleBox 部署、PM2 守护、日志轮转、开机自启
# =====================================================

# ---------- 全局配置 ----------
set -euo pipefail

readonly PROJECT_DIR="/root/telebox-data"
readonly NODE_VERSION="20"
readonly GITHUB_REPO="https://github.com/TeleBoxDev/TeleBox.git"

# ---------- 颜色输出 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查是否为 root
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 错误: 请使用 root 用户运行此脚本 (sudo 或直接 root 登录)"
  exit 1
fi

# ---------- 错误处理 ----------
handle_error() {
    echo -e "${RED}错误: 脚本执行在第 $1 行失败，请检查上方日志输出。${NC}"
    exit 1
}
trap 'handle_error $LINENO' ERR

# ---------- 用户交互 ----------
confirm() {
    echo
    read -p "$1 (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# ---------- 清理旧 TeleBox ----------
cleanup_telebox() {
    echo -e "${YELLOW}==== 清理旧 TeleBox 安装 ====${NC}"

    # 停止并删除 PM2 中的 TeleBox 服务
    if command -v pm2 >/dev/null 2>&1; then
        echo -e "${BLUE}停止 PM2 服务...${NC}"
        pm2 delete telebox 2>/dev/null || true
    fi

    # 杀掉可能残留的进程
    echo -e "${BLUE}终止残留 TeleBox 进程...${NC}"
    pkill -f "telebox" 2>/dev/null || true
    pkill -f "npm.*start.*telebox" 2>/dev/null || true
    pkill -f "node.*telebox" 2>/dev/null || true

    sleep 2

    # 删除项目目录
    if [ -d "$PROJECT_DIR" ]; then
        echo -e "${BLUE}删除项目目录 $PROJECT_DIR ...${NC}"
        rm -rf "$PROJECT_DIR"
    fi

    # 删除缓存
    echo -e "${BLUE}清理缓存文件...${NC}"
    rm -rf "/tmp/telebox"* "/root/.telebox"* 2>/dev/null || true

    echo -e "${GREEN}清理完成！${NC}"
    echo
}

# ---------- 安装系统依赖 ----------
install_dependencies() {
    echo -e "${BLUE}==== 安装系统依赖 ====${NC}"
    apt update
    apt install -y curl git build-essential libvips libvips-dev
}

# ---------- 安装 Node.js ----------
install_node() {
    echo -e "${BLUE}==== 安装 Node.js v${NODE_VERSION} ====${NC}"
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash -
    apt install -y nodejs
    echo -e "${GREEN}Node.js 版本: $(node -v)${NC}"
    echo -e "${GREEN}npm 版本: $(npm -v)${NC}"
}

# ---------- 克隆 TeleBox 项目 ----------
setup_application() {
    echo -e "${BLUE}==== 下载 TeleBox 项目 ====${NC}"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"

    if [ -d ".git" ]; then
        echo -e "${YELLOW}检测到已有项目，执行 git pull 更新...${NC}"
        git pull
    else
        git clone "$GITHUB_REPO" .
    fi

    echo -e "${BLUE}==== 安装项目依赖 ====${NC}"
    npm install
    npm rebuild sharp
}

# ---------- 首次登录配置 ----------
configure_login() {
    echo -e "${YELLOW}==== 首次启动 TeleBox 进行 Telegram 登录 ====${NC}"
    echo -e "${GREEN}请按提示输入 Telegram API 信息：${NC}"
    echo -e "1. api_id 和 api_hash 可从 https://my.telegram.org 获取"
    echo -e "2. 登录时输入国际区号格式的手机号，例如 +8613812345678"
    echo -e "3. 登录成功后看到 'You should now be connected.' 再按 Ctrl+C 停止"
    echo
    read -p "按回车键开始首次登录..." -r

    cd "$PROJECT_DIR"
    npm start || true
    echo -e "${GREEN}首次登录完成，准备后台运行...${NC}"
}

# ---------- 配置 PM2 ----------
setup_pm2() {
    echo -e "${BLUE}==== 安装 PM2 并配置守护进程 ====${NC}"
    npm install -g pm2

    cd "$PROJECT_DIR"

    # 创建 PM2 配置文件
    cat > "$PROJECT_DIR/ecosystem.config.js" <<'EOF'
module.exports = {
  apps: [
    {
      name: "telebox",
      script: "npm",
      args: "start",
      cwd: __dirname,
      error_file: "./logs/error.log",
      out_file: "./logs/out.log",
      merge_logs: true,
      time: true,
      autorestart: true,
      max_restarts: 10,
      min_uptime: "10s",
      restart_delay: 4000,
      env: {
        NODE_ENV: "production"
      }
    }
  ]
}
EOF

    # 启动 TeleBox
    mkdir -p "$PROJECT_DIR/logs"
    pm2 start ecosystem.config.js
    pm2 save

    # 配置开机自启（root 用户专用）
    pm2 startup systemd -u root --hp /root
}

# ---------- 日志轮转 ----------
setup_logrotate() {
    echo -e "${BLUE}==== 安装 PM2 日志轮转 ====${NC}"
    pm2 install pm2-logrotate
    pm2 set pm2-logrotate:max_size 10M
    pm2 set pm2-logrotate:retain 7
}

# ---------- 显示完成信息 ----------
show_completion_info() {
    echo
    echo -e "${GREEN}==== TeleBox 安装完成 ====${NC}"
    echo -e "项目目录: ${YELLOW}$PROJECT_DIR${NC}"
    echo
    echo -e "${BLUE}常用管理命令：${NC}"
    echo "查看状态: pm2 status telebox"
    echo "查看日志: pm2 logs telebox"
    echo "实时日志: pm2 logs telebox --lines 50"
    echo "重启服务: pm2 restart telebox"
    echo "停止服务: pm2 stop telebox"
    echo "删除服务: pm2 delete telebox"
    echo
    echo -e "${GREEN}TeleBox 已通过 PM2 守护运行，并配置了日志轮转和开机自启！${NC}"
}

# ---------- 主安装流程 ----------
main() {
    echo -e "${GREEN}TeleBox 自动安装脚本${NC}"
    echo -e "${YELLOW}适用于 Debian 12 且需 root 用户运行${NC}"
    echo

    if confirm "是否清理旧版本 TeleBox 并重新安装？"; then
        cleanup_telebox
    else
        echo -e "${YELLOW}跳过清理步骤${NC}"
    fi

    install_dependencies
    install_node
    setup_application
    configure_login
    setup_pm2
    setup_logrotate
    show_completion_info
}

main "$@"
