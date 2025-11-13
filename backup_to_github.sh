#!/bin/bash
set -e

APP_DIR="/opt/tg_multi_bot"
SERVICE_NAME="tg_multi_bot"
SCRIPT_NAME="host_bot.py"
SCRIPT_URL="https://raw.githubusercontent.com/ryty1/TG_Talk/main/host_bot.py"
BACKUP_SCRIPT_NAME="backup_to_github.sh"
CRON_JOB_NAME="tg_bot_backup"

function check_and_install() {
  PKG=$1
  if ! dpkg -s "$PKG" >/dev/null 2>&1; then
    echo "📦 安装 $PKG ..."
    apt install -y -qq "$PKG" >/dev/null 2>&1
  else
    echo "✅ 已安装 $PKG，跳过"
  fi
}

function create_backup_script() {
  echo "📦 创建 GitHub 备份脚本..."
  cat << 'EOF' > "$APP_DIR/$BACKUP_SCRIPT_NAME"
#!/bin/bash
set -e

APP_DIR="/opt/tg_multi_bot"
BACKUP_DIR="/tmp/tg_bot_backup"
REPO_URL="https://github.com/ryty1/TG_Talk.git"
BRANCH="main"
BACKUP_BRANCH="backup-data"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
  echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] 警告: $1${NC}"
}

error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] 错误: $1${NC}"
}

# 检查必要文件
if [ ! -f "$APP_DIR/.env" ]; then
  error "未找到环境配置文件 .env"
  exit 1
fi

# 创建备份目录
mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR"

# 克隆仓库
log "克隆仓库..."
if [ -d ".git" ]; then
  git pull origin "$BRANCH"
else
  git clone -b "$BRANCH" "$REPO_URL" .
fi

# 创建备份分支（如果不存在）
if ! git branch -a | grep -q "remotes/origin/$BACKUP_BRANCH"; then
  log "创建备份分支 $BACKUP_BRANCH..."
  git checkout -b "$BACKUP_BRANCH"
else
  git checkout "$BACKUP_BRANCH"
  git pull origin "$BACKUP_BRANCH"
fi

# 创建备份目录结构
mkdir -p "backup/$(hostname)"

# 备份重要文件
log "备份数据文件..."
cp "$APP_DIR/.env" "backup/$(hostname)/"
cp "$APP_DIR/bot_data.json" "backup/$(hostname)/" 2>/dev/null || warn "未找到 bot_data.json"
cp "$APP_DIR/user_data.json" "backup/$(hostname)/" 2>/dev/null || warn "未找到 user_data.json"

# 备份系统服务状态
log "备份系统服务状态..."
systemctl status "$SERVICE_NAME" > "backup/$(hostname)/service_status.log" 2>/dev/null || warn "无法获取服务状态"

# 添加和提交更改
git add backup/
if git diff --staged --quiet; then
  log "没有变化需要提交"
else
  log "提交备份..."
  git commit -m "自动备份: $(date '+%Y-%m-%d %H:%M:%S') - $(hostname)"
  
  # 推送到 GitHub
  log "推送到 GitHub..."
  if git push origin "$BACKUP_BRANCH"; then
    log "✅ 备份完成！"
  else
    error "推送失败，请检查 GitHub 令牌权限"
    exit 1
  fi
fi

# 清理
cd /
rm -rf "$BACKUP_DIR"
EOF

  chmod +x "$APP_DIR/$BACKUP_SCRIPT_NAME"
  echo "✅ 备份脚本创建完成"
}

function setup_github_backup() {
  echo "🔐 设置 GitHub 自动备份..."
  
  # 检查是否已配置 Git 用户信息
  if ! git config --global user.name || ! git config --global user.email; then
    echo "⚠️ 未配置 Git 用户信息，正在设置..."
    git config --global user.name "TG Bot Backup"
    git config --global user.email "bot@backup.com"
  fi

  # 检查 GitHub 令牌
  read -p "请输入 GitHub 个人访问令牌 (PAT): " GITHUB_TOKEN
  if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ 未提供 GitHub 令牌，跳过备份设置"
    return 1
  fi

  # 测试令牌有效性
  echo "🔍 验证 GitHub 令牌..."
  if curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user | grep -q "login"; then
    echo "✅ GitHub 令牌验证成功"
  else
    echo "❌ GitHub 令牌无效，请检查令牌权限"
    return 1
  fi

  # 配置 Git 凭证存储
  echo "https://${GITHUB_TOKEN}:x-oauth-basic@github.com" > "$APP_DIR/git_credentials"
  git config --global credential.helper "store --file=$APP_DIR/git_credentials"

  # 创建备份脚本
  create_backup_script

  # 设置定时任务
  echo "⏰ 设置每天 2:00 自动备份..."
  CRON_JOB="0 2 * * * $APP_DIR/$BACKUP_SCRIPT_NAME >> $APP_DIR/backup.log 2>&1"
  
  # 移除现有任务（如果存在）
  (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_NAME") | crontab -
  # 添加新任务
  (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
  
  echo "✅ 自动备份设置完成！"
  echo "📅 备份时间: 每天 2:00"
  echo "📁 备份分支: backup-data"
  echo "📝 日志文件: $APP_DIR/backup.log"
}

function manual_backup() {
  echo "🔁 执行手动备份..."
  if [ -f "$APP_DIR/$BACKUP_SCRIPT_NAME" ]; then
    bash "$APP_DIR/$BACKUP_SCRIPT_NAME"
  else
    echo "❌ 备份脚本不存在，请先安装 Bot 管理平台"
  fi
}

function install_bot() {
  echo "📦 检查系统依赖..."
  apt update -qq >/dev/null 2>&1
  check_and_install python3
  check_and_install python3-venv
  check_and_install python3-pip
  check_and_install git
  check_and_install curl

  echo "📂 创建项目目录..."
  mkdir -p "$APP_DIR"
  cd "$APP_DIR"

  echo "👾 下载 $SCRIPT_NAME ..."
  curl -sL -o "$SCRIPT_NAME" "$SCRIPT_URL"
  echo "✅ 已下载最新 $SCRIPT_NAME"

  echo "🐍 创建虚拟环境..."
  if [ ! -d venv ]; then
    python3 -m venv venv >/dev/null 2>&1
  fi
  source venv/bin/activate

  echo "⬆️ 检查 Python 依赖..."
  pip install --upgrade pip >/dev/null 2>&1

  PTB_VERSION=$(pip show python-telegram-bot 2>/dev/null | grep Version | awk '{print $2}' || true)
  if [ "$PTB_VERSION" != "20.7" ]; then
    echo "📦 安装 python-telegram-bot==20.7 ..."
    pip install -q "python-telegram-bot==20.7"
  else
    echo "✅ 已安装 python-telegram-bot==20.7，跳过"
  fi

  if ! pip show python-dotenv >/dev/null 2>&1; then
    echo "📦 安装 python-dotenv ..."
    pip install -q python-dotenv
  else
    echo "✅ 已安装 python-dotenv，跳过"
  fi

  # ------------------ 环境变量 ------------------
  echo "⚙️ 生成环境变量 (.env)..."
  # 输入宿主 Bot Token
  while true; do
      read -p "请输入宿主 Bot 的 Token: " MANAGER_TOKEN
      if [ -n "$MANAGER_TOKEN" ]; then
          break
      else
          echo "❌ BOT_TOKEN 不能为空，请重新输入"
      fi
  done

  # 输入管理频道/群ID
  while true; do
      read -p "请输入宿主 TG_CHAT_ID : " ADMIN_CHANNEL
      if [ -n "$ADMIN_CHANNEL" ]; then
          break
      else
          echo "❌ 宿主 TG_CHAT_ID 不能为空，请重新输入"
      fi
  done

  # 写入 .env
  cat <<EOF > .env
MANAGER_TOKEN=$MANAGER_TOKEN
ADMIN_CHANNEL=$ADMIN_CHANNEL
EOF
  echo "✅ 已生成 .env 配置文件"

  # ------------------ Systemd 服务 ------------------
  echo "🛠️ 配置 systemd 服务..."
  cat <<EOF >/etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=Telegram Multi Bot Host
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/$SCRIPT_NAME
Restart=always
RestartSec=3
EnvironmentFile=$APP_DIR/.env

[Install]
WantedBy=multi-user.target
EOF

  echo "🚀 启动并设置开机自启..."
  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable $SERVICE_NAME.service >/dev/null 2>&1
  systemctl restart $SERVICE_NAME.service >/dev/null 2>&1

  # 设置 GitHub 备份
  echo "📦 设置自动备份功能..."
  read -p "是否设置 GitHub 自动备份? (y/n): " setup_backup
  if [[ $setup_backup =~ ^[Yy]$ ]]; then
    setup_github_backup
  else
    echo "⚠️ 跳过自动备份设置"
  fi

  echo "✅ 部署完成！使用命令查看日志："
  echo "   journalctl -u $SERVICE_NAME.service -f"
}

function uninstall_bot() {
  echo "🛑 停止服务..."
  systemctl stop $SERVICE_NAME.service >/dev/null 2>&1 || true

  echo "❌ 禁用开机自启..."
  systemctl disable $SERVICE_NAME.service >/dev/null 2>&1 || true

  echo "🗑️ 删除定时备份任务..."
  (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_NAME") | crontab -

  echo "🗑️ 删除 systemd 服务文件..."
  if [ -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
      rm -f "/etc/systemd/system/$SERVICE_NAME.service"
      systemctl daemon-reload >/dev/null 2>&1
      echo "✅ 已删除 $SERVICE_NAME.service"
  else
      echo "⚠️ 没有找到 systemd 服务文件"
  fi

  echo "🗂️ 删除项目目录 $APP_DIR ..."
  if [ -d "$APP_DIR" ]; then
      rm -rf "$APP_DIR"
      echo "✅ 已删除 $APP_DIR"
  else
      echo "⚠️ 项目目录不存在"
  fi

  echo "✅ 卸载完成！"
}

# ------------------ 菜单 ------------------
while true; do
  echo "============================"
  echo "   Telegram 多 Bot 管理脚本"
  echo "   双向 机器人 自用托管平台   "
  echo "============================"
  echo "1) 安装 Bot 管理平台"
  echo "2) 卸载 Bot 管理平台"
  echo "3) 手动执行备份"
  echo "4) 返回 VIP 工具箱"
  read -p "请选择操作 [1-4]: " choice

  case "$choice" in
    1)
      install_bot
      ;;
    2)
      uninstall_bot
      ;;
    3)
      manual_backup
      ;;
    4)
      bash <(curl -Ls https://raw.githubusercontent.com/ryty1/Checkin/refs/heads/main/vip.sh)
      ;;
    *)
      echo "❌ 无效选择，请输入 1-4"
      ;;
  esac
done
