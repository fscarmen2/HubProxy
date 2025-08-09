#!/bin/bash

# 版本信息
VERSION="1.0.1"
UPDATE_DATE="2025-08-08"

# 更新日志
# v1.0.1 (2025-08-08)
# - 优化 Zone ID 获取方式：通过 API 自动获取，无需用户手动输入
# - VPS 卸载增强：卸载时可选择是否一并卸载 Caddy，默认保留 Caddy
# v1.0.0 (2025-07-30)
# - 开箱即用的深度整合方案：从证书申请到HTTPS反代全程自动化，为HubProxy提供完整的Docker/宿主机双栈加速服务
# - 支持VPS和Docker双方案部署
# - 集成Cloudflare API，自动创建和配置DNS记录
# - 自动申请和维护SSL证书
# - 支持IPv4/IPv6双栈环境
# - 一键部署和卸载功能

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
REPO="sky22333/hubproxy"
GITHUB_API="https://api.github.com/repos/${REPO}"
GITHUB_RELEASES="${GITHUB_API}/releases"
SERVICE_NAME="hubproxy"
INSTALL_DIR="/opt/hubproxy"
CONFIG_FILE="config.toml"
BINARY_NAME="hubproxy"
LOG_DIR="/var/log/hubproxy"
TEMP_DIR="/tmp/hubproxy-install"
CADDYFILE="/etc/caddy/Caddyfile"

echo -e "${RED}HubProxy with Caddy and Cloudflare 集成一键安装脚本${NC}"
echo -e "${GREEN}版本: ${BLUE}${VERSION}  ${GREEN}更新日期: ${BLUE}${UPDATE_DATE}${NC}"
echo -e "${GREEN}更新日志: ${BLUE}开箱即用的深度整合方案 - 从证书申请到HTTPS反代全程自动化，为HubProxy提供完整的Docker/宿主机双栈加速服务。${NC}"
echo "==============================================================="

# 检查是否以root权限运行
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}此脚本需要root权限运行${NC}"
  echo "请使用: su root -c \"$0\" 或在root用户下运行此脚本"
  exit 1
fi

# 检查已安装的方案
check_installed_schemes() {
  VPS_INSTALLED=false
  DOCKER_INSTALLED=false

  # 检查VPS方案是否已安装
  if [ -d "${INSTALL_DIR}" ] || systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null; then
    VPS_INSTALLED=true
  fi

  # 检查Docker方案是否已安装
  if [ -d "/root/hubproxy" ] && [ -f "/root/hubproxy/docker-compose.yml" ]; then
    DOCKER_INSTALLED=true
  fi
}

# 选择安装方案
select_installation_method() {
  # 检查已安装的方案
  check_installed_schemes

  echo -e "${BLUE}请选择操作:${NC}"
  echo "1) 安装 - VPS方案 (默认)"
  echo "2) 安装 - Docker方案"

  # 只有当有已安装的方案时才显示卸载选项
  if [ "$VPS_INSTALLED" = true ] || [ "$DOCKER_INSTALLED" = true ]; then
    echo "3) 卸载"
  fi

  # 根据是否有已安装的方案调整默认选项和读取范围
  if [ "$VPS_INSTALLED" = true ] || [ "$DOCKER_INSTALLED" = true ]; then
    read -p "请输入选项 (1-3, 默认为1): " INSTALL_METHOD
    INSTALL_METHOD=${INSTALL_METHOD:-1}
  else
    read -p "请输入选项 (1-2, 默认为1): " INSTALL_METHOD
    INSTALL_METHOD=${INSTALL_METHOD:-1}
  fi

  case $INSTALL_METHOD in
    1)
      echo -e "${GREEN}已选择 VPS 安装方案${NC}"
      INSTALL_TYPE="vps"
      OPERATION="install"
      ;;
    2)
      echo -e "${GREEN}已选择 Docker 安装方案${NC}"
      INSTALL_TYPE="docker"
      OPERATION="install"
      ;;
    3)
      # 只有当有已安装的方案时才允许选择卸载
      if [ "$VPS_INSTALLED" = true ] || [ "$DOCKER_INSTALLED" = true ]; then
        echo -e "${GREEN}已选择卸载${NC}"
        OPERATION="uninstall"
        select_uninstall_method
      else
        echo -e "${YELLOW}无效选项，使用默认 VPS 安装方案${NC}"
        INSTALL_TYPE="vps"
        OPERATION="install"
      fi
      ;;
    *)
      echo -e "${YELLOW}无效选项，使用默认 VPS 安装方案${NC}"
      INSTALL_TYPE="vps"
      OPERATION="install"
      ;;
  esac
}

# 选择卸载方案
select_uninstall_method() {
  # 检查已安装的方案
  check_installed_schemes

  # 如果只安装了一种方案，直接卸载该方案
  if [ "$VPS_INSTALLED" = true ] && [ "$DOCKER_INSTALLED" = false ]; then
    echo -e "${GREEN}检测到已安装 VPS 方案，将卸载该方案${NC}"
    INSTALL_TYPE="vps"
    return
  elif [ "$VPS_INSTALLED" = false ] && [ "$DOCKER_INSTALLED" = true ]; then
    echo -e "${GREEN}检测到已安装 Docker 方案，将卸载该方案${NC}"
    INSTALL_TYPE="docker"
    return
  fi

  # 如果两种方案都安装了，让用户选择
  echo -e "${BLUE}检测到已安装多个方案，请选择要卸载的方案:${NC}"
  echo "1) VPS方案 (默认)"
  echo "2) Docker方案"

  read -p "请输入选项 (1-2, 默认为1): " UNINSTALL_METHOD
  UNINSTALL_METHOD=${UNINSTALL_METHOD:-1}

  case $UNINSTALL_METHOD in
    1)
      echo -e "${GREEN}已选择 VPS 卸载方案${NC}"
      INSTALL_TYPE="vps"
      ;;
    2)
      echo -e "${GREEN}已选择 Docker 卸载方案${NC}"
      INSTALL_TYPE="docker"
      ;;
    *)
      echo -e "${YELLOW}无效选项，使用默认 VPS 卸载方案${NC}"
      INSTALL_TYPE="vps"
      ;;
  esac
}

# 检查命令是否存在
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# 检查是否有可用的JSON处理工具
has_json_tool() {
  # 检查是否有 jq
  if command_exists jq; then
    JSON_TOOL="jq"
    return 0
  fi

  return 1
}

# 检测操作系统
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
  else
    echo -e "${RED}错误: 无法从 /etc/os-release 检测操作系统${NC}"
    exit 1
  fi
  echo -e "${GREEN}检测到操作系统: $OS $OS_VERSION${NC}"
}

# 安装系统依赖
install_system_dependencies() {
  echo -e "${BLUE}检查并安装系统依赖...${NC}"

  detect_os

  # 确定要使用的获取工具（curl 或 wget）
  if command_exists curl; then
    FETCH_TOOL="curl"
    echo -e "${GREEN}使用 curl 作为下载工具${NC}"
  elif command_exists wget; then
    FETCH_TOOL="wget"
    echo -e "${GREEN}使用 wget 作为下载工具${NC}"
  else
    echo -e "${YELLOW}未安装 curl 或 wget，正在安装 curl...${NC}"
    if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ] || [ "$OS" == "raspbian" ]; then
      apt update &>/dev/null && apt install -y curl &>/dev/null
    elif [ "$OS" == "fedora" ]; then
      dnf install -y curl &>/dev/null
    elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
      if [ "$OS_VERSION" == "7" ]; then
        yum install -y curl &>/dev/null
      else
        dnf install -y curl &>/dev/null
      fi
    elif [ "$OS" == "arch" ] || [ "$OS" == "manjaro" ] || [ "$OS" == "parabola" ]; then
      pacman -Syu --noconfirm curl &>/dev/null
    fi
    FETCH_TOOL="curl"
    echo -e "${GREEN}curl 安装完成${NC}"
  fi

  # 检查需要的其他依赖
  missing_deps=()
  for cmd in tar jq; do
    if ! command_exists $cmd; then
      missing_deps+=($cmd)
    fi
  done

  if [ ${#missing_deps[@]} -gt 0 ]; then
    echo -e "${YELLOW}检测到缺少依赖: ${missing_deps[*]}${NC}"
    echo -e "${BLUE}正在自动安装依赖...${NC}"

    if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ] || [ "$OS" == "raspbian" ]; then
      apt install -y "${missing_deps[@]}" &>/dev/null
    elif [ "$OS" == "fedora" ]; then
      dnf install -y "${missing_deps[@]}" &>/dev/null
    elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
      if [ "$OS_VERSION" == "7" ]; then
        yum install -y "${missing_deps[@]}" &>/dev/null
      else
        dnf install -y "${missing_deps[@]}" &>/dev/null
      fi
    elif [ "$OS" == "arch" ] || [ "$OS" == "manjaro" ] || [ "$OS" == "parabola" ]; then
      pacman -Syu --noconfirm "${missing_deps[@]}" &>/dev/null
    fi

    if [ $? -ne 0 ]; then
      echo -e "${RED}依赖安装失败${NC}"
      exit 1
    fi

    echo -e "${GREEN}依赖安装成功${NC}"

    # 重新检查JSON工具
    if ! has_json_tool; then
      echo -e "${RED}无法找到可用的JSON处理工具${NC}"
      exit 1
    fi
  else
    echo -e "${GREEN}所有依赖已安装${NC}"
  fi
}

# 安装 Caddy
install_caddy() {
  # 检查 Caddy 是否已安装
  if command_exists caddy; then
    CADDY_VERSION=$(caddy version | awk 'NR==1 {print $1}')
    echo -e "${GREEN}Caddy 已安装，版本: $CADDY_VERSION${NC}"
    return 0
  fi

  echo -e "${YELLOW}正在安装 Caddy...${NC}"

  if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ] || [ "$OS" == "raspbian" ]; then
    # 安装依赖
    apt install -y debian-keyring debian-archive-keyring apt-transport-https &>/dev/null

    # 获取 gpg 密钥（仅当文件不存在时）
    if [ ! -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg ]; then
      if [ "$FETCH_TOOL" == "curl" ]; then
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg &>/dev/null
      else
        wget -qO- 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg &>/dev/null
      fi
    fi

    # 获取 debian.list（仅当文件不存在时）
    if [ ! -f /etc/apt/sources.list.d/caddy-stable.list ]; then
      if [ "$FETCH_TOOL" == "curl" ]; then
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list 2>/dev/null
      else
        wget -qO- 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list 2>/dev/null
      fi
    fi

    # 设置权限
    chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg &>/dev/null
    chmod o+r /etc/apt/sources.list.d/caddy-stable.list &>/dev/null

    # 更新 apt
    apt update &>/dev/null

    # 安装 caddy
    apt install -y caddy &>/dev/null
  elif [ "$OS" == "fedora" ]; then
    # Fedora
    dnf install -y 'dnf-command(copr)' &>/dev/null
    dnf copr enable -y @caddy/caddy &>/dev/null
    dnf install -y caddy &>/dev/null
  elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
    # RHEL/CentOS
    if [ "$OS_VERSION" == "7" ]; then
      # RHEL/CentOS 7
      yum install -y yum-plugin-copr &>/dev/null
      yum copr enable -y @caddy/caddy &>/dev/null
      yum install -y caddy &>/dev/null
    else
      # RHEL/CentOS 8+
      dnf install -y 'dnf-command(copr)' &>/dev/null
      dnf copr enable -y @caddy/caddy &>/dev/null
      dnf install -y caddy &>/dev/null
    fi
  elif [ "$OS" == "arch" ] || [ "$OS" == "manjaro" ] || [ "$OS" == "parabola" ]; then
    # Arch Linux/Manjaro/Parabola
    pacman -Syu --noconfirm caddy &>/dev/null
  else
    echo -e "${RED}错误: 不支持在 $OS 上安装${NC}"
    exit 1
  fi

  echo -e "${GREEN}Caddy 安装完成${NC}"
}

# 安装 Docker
install_docker() {
  echo -e "${BLUE}检查并安装 Docker...${NC}"

  # 检查 Docker 是否已安装
  if command_exists docker; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
    echo -e "${GREEN}Docker 已安装，版本: $DOCKER_VERSION${NC}"
    return 0
  fi

  echo -e "${YELLOW}正在安装 Docker...${NC}"

  if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ] || [ "$OS" == "raspbian" ]; then
    # 添加 Docker 官方 GPG 密钥
    apt-get update &>/dev/null
    apt-get install -y ca-certificates curl gnupg &>/dev/null

    # 创建目录
    install -m 0755 -d /etc/apt/keyrings &>/dev/null

    # 下载并添加 GPG 密钥
    if [ "$OS" == "ubuntu" ]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc &>/dev/null
    elif [ "$OS" == "debian" ]; then
      curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc &>/dev/null
    else  # raspbian
      curl -fsSL https://download.docker.com/linux/raspbian/gpg -o /etc/apt/keyrings/docker.asc &>/dev/null
    fi

    chmod a+r /etc/apt/keyrings/docker.asc &>/dev/null

    # 添加仓库到 Apt 源
    if [ "$OS" == "ubuntu" ]; then
      echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    elif [ "$OS" == "debian" ]; then
      echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    else  # raspbian
      echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/raspbian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi

    # 更新并安装 Docker
    apt-get update &>/dev/null
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &>/dev/null
  elif [ "$OS" == "fedora" ]; then
    dnf -y install dnf-plugins-core &>/dev/null
    dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo &>/dev/null
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &>/dev/null
    systemctl enable --now docker &>/dev/null
  elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
    dnf -y install dnf-plugins-core &>/dev/null
    dnf config-manager --add-repo https://download.docker.com/linux/"$OS"/docker-ce.repo &>/dev/null
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &>/dev/null
    systemctl enable --now docker &>/dev/null
  elif [ "$OS" == "arch" ] || [ "$OS" == "manjaro" ] || [ "$OS" == "parabola" ]; then
    pacman -Syu --noconfirm docker docker-compose &>/dev/null
    systemctl enable --now docker &>/dev/null
  else
    echo -e "${RED}错误: 不支持在 $OS 上安装 Docker${NC}"
    exit 1
  fi

  # 启动 Docker 服务（除 Fedora/CentOS/RHEL/Arch 外）
  if [[ ! "$OS" =~ ^(fedora|centos|rhel|arch|manjaro|parabola)$ ]]; then
    systemctl enable --now docker &>/dev/null
  fi

  echo -e "${GREEN}Docker 安装完成${NC}"
}

# 检测系统架构
detect_arch() {
  local arch=$(uname -m)
  case $arch in
    x86_64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    *)
      echo -e "${RED}不支持的架构: $arch${NC}"
      exit 1
      ;;
  esac
}

# 安装 HubProxy
install_hubproxy() {
  ARCH=$(detect_arch)
  echo -e "${BLUE}检测到架构: linux-${ARCH}${NC}"

  # 检查是否为本地安装模式
  if [ -f "${BINARY_NAME}" ]; then
    echo -e "${BLUE}发现本地文件，使用本地安装模式${NC}"
    LOCAL_INSTALL=true
  else
    echo -e "${BLUE}本地无文件，使用自动下载模式${NC}"
    LOCAL_INSTALL=false

    # 自动下载功能
    if [ "$LOCAL_INSTALL" = false ]; then
      echo -e "${BLUE}获取最新版本信息...${NC}"
      if [ "$FETCH_TOOL" == "curl" ]; then
        LATEST_RELEASE=$(curl -s "${GITHUB_RELEASES}/latest")
      else
        LATEST_RELEASE=$(wget -qO- "${GITHUB_RELEASES}/latest")
      fi

      if [ $? -ne 0 ]; then
        echo -e "${RED}无法获取版本信息${NC}"
        exit 1
      fi

      VERSION=$(echo "$LATEST_RELEASE" | jq -r '.tag_name')
      if [ "$VERSION" = "null" ]; then
        echo -e "${RED}无法解析版本信息${NC}"
        exit 1
      fi

      echo -e "${GREEN}最新版本: ${VERSION}${NC}"

      # 构造下载URL
      ASSET_NAME="hubproxy-${VERSION}-linux-${ARCH}.tar.gz"
      DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET_NAME}"

      echo -e "${BLUE}下载: ${ASSET_NAME}${NC}"

      # 创建临时目录并下载
      rm -rf "${TEMP_DIR}"
      mkdir -p "${TEMP_DIR}"
      cd "${TEMP_DIR}"

      if [ "$FETCH_TOOL" == "curl" ]; then
        curl -sSL -o "${ASSET_NAME}" "${DOWNLOAD_URL}"
      else
        wget -q -O "${ASSET_NAME}" "${DOWNLOAD_URL}"
      fi

      if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败${NC}"
        exit 1
      fi

      # 解压
      tar -xzf "${ASSET_NAME}"
      if [ $? -ne 0 ] || [ ! -d "hubproxy" ]; then
        echo -e "${RED}解压失败${NC}"
        exit 1
      fi

      cd hubproxy
      echo -e "${GREEN}下载完成${NC}"
    fi
  fi

  echo -e "${YELLOW}开始安装 HubProxy...${NC}"

  # 停止现有服务（如果存在）
  if systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null; then
    echo -e "${YELLOW}停止现有服务...${NC}"
    systemctl stop ${SERVICE_NAME}
  fi

  # 备份现有配置（如果存在）
  CONFIG_BACKUP_EXISTS=false
  if [ -f "${INSTALL_DIR}/${CONFIG_FILE}" ]; then
    echo -e "${BLUE}备份现有配置...${NC}"
    cp "${INSTALL_DIR}/${CONFIG_FILE}" "${TEMP_DIR}/config.toml.backup"
    CONFIG_BACKUP_EXISTS=true
  fi

  # 1. 创建目录结构
  echo -e "${BLUE}创建目录结构${NC}"
  mkdir -p ${INSTALL_DIR}
  mkdir -p ${LOG_DIR}
  chmod 755 ${INSTALL_DIR}
  chmod 755 ${LOG_DIR}

  # 2. 复制二进制文件
  echo -e "${BLUE}复制二进制文件${NC}"
  cp "${BINARY_NAME}" "${INSTALL_DIR}/"
  chmod +x "${INSTALL_DIR}/${BINARY_NAME}"

  # 3. 复制配置文件
  echo -e "${BLUE}复制配置文件${NC}"
  if [ -f "${CONFIG_FILE}" ]; then
    if [ "$CONFIG_BACKUP_EXISTS" = false ]; then
      cp "${CONFIG_FILE}" "${INSTALL_DIR}/"
      echo -e "${GREEN}配置文件复制成功${NC}"
    else
      echo -e "${YELLOW}保留现有配置文件${NC}"
    fi
  else
    echo -e "${YELLOW}配置文件不存在，将使用默认配置${NC}"
  fi

  # 4. 安装systemd服务文件
  echo -e "${BLUE}安装systemd服务文件${NC}"
  cp "${SERVICE_NAME}.service" "/etc/systemd/system/"
  systemctl daemon-reload

  # 5. 恢复配置文件（如果有备份）
  if [ "$CONFIG_BACKUP_EXISTS" = true ]; then
    echo -e "${BLUE}恢复配置文件...${NC}"
    cp "${TEMP_DIR}/config.toml.backup" "${INSTALL_DIR}/${CONFIG_FILE}"
  fi

  # 6. 启用并启动服务
  echo -e "${BLUE}启用并启动服务${NC}"
  systemctl enable ${SERVICE_NAME}
  systemctl start ${SERVICE_NAME}

  # 7. 清理临时文件
  if [ "$LOCAL_INSTALL" = false ]; then
    echo -e "${BLUE}清理临时文件...${NC}"
    cd /
    rm -rf "${TEMP_DIR}"
  fi

  # 8. 检查服务状态
  sleep 2
  if systemctl is-active --quiet ${SERVICE_NAME}; then
    echo -e "${GREEN}HubProxy 安装成功！${NC}"
    echo -e "${GREEN}默认运行端口: 5000${NC}"
    echo -e "${GREEN}配置文件路径: ${INSTALL_DIR}/${CONFIG_FILE}${NC}"
  else
    echo -e "${RED}服务启动失败${NC}"
    echo "查看错误日志: sudo journalctl -u ${SERVICE_NAME} -f"
    exit 1
  fi
}

# 获取 IP 地址
get_ip_addresses() {
  echo -e "${BLUE}获取 IP 地址信息...${NC}"

  # 尝试获取 IPv4
  if [ "$FETCH_TOOL" == "curl" ]; then
    IPV4=$(curl -4s https://icanhazip.com 2>/dev/null || curl -4s http://ipinfo.io/ip 2>/dev/null || true)
  else
    IPV4=$(wget -4qO- https://icanhazip.com 2>/dev/null || $FETCH_TOOL -4qO- http://ipinfo.io/ip 2>/dev/null || true)
  fi

  if [ -n "$IPV4" ]; then
    echo -e "${GREEN}检测到 IPv4: $IPV4${NC}"
  else
    echo -e "${YELLOW}未检测到 IPv4${NC}"
  fi

  # 尝试获取 IPv6
  if [ "$FETCH_TOOL" == "curl" ]; then
    IPV6=$(curl -6s https://icanhazip.com 2>/dev/null || curl -6s http://ipinfo.io/ip 2>/dev/null || true)
  else
    IPV6=$(wget -6qO- https://icanhazip.com 2>/dev/null || wget -6qO- http://ipinfo.io/ip 2>/dev/null || true)
  fi

  if [ -n "$IPV6" ]; then
    echo -e "${GREEN}检测到 IPv6: $IPV6${NC}"
  else
    echo -e "${YELLOW}未检测到 IPv6${NC}"
  fi

  # 如果都没有获取到，报错
  if [ -z "$IPV4" ] && [ -z "$IPV6" ]; then
    echo -e "${RED}无法获取公网 IP 地址${NC}"
    exit 1
  fi
}

# 验证 IPv4 地址格式
validate_ipv4() {
  local ip=$1
  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    IFS='.' read -ra ADDR <<< "$ip"
    for i in "${ADDR[@]}"; do
      if [[ $i -gt 255 ]]; then
        return 1
      fi
    done
    return 0
  else
    return 1
  fi
}

# 验证 IPv6 地址格式
validate_ipv6() {
  local ip=$1
  if [[ $ip =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]]; then
    return 0
  else
    return 1
  fi
}

# 选择 IP 地址
select_ip_address() {
  echo -e "${BLUE}选择用于 DNS 记录的 IP 地址:${NC}"

  OPTIONS=()
  if [ -n "$IPV4" ]; then
    OPTIONS+=("IPv4: $IPV4")
  fi
  if [ -n "$IPV6" ]; then
    OPTIONS+=("IPv6: $IPV6")
  fi
  OPTIONS+=("自定义 IP 地址")

  select opt in "${OPTIONS[@]}"; do
    case $REPLY in
      1)
        if [ -n "$IPV4" ]; then
          SELECTED_IP=$IPV4
          echo -e "${GREEN}已选择 IPv4: $SELECTED_IP${NC}"
          break
        else
          echo -e "${RED}无效选项${NC}"
        fi
        ;;
      2)
        if [ -n "$IPV6" ]; then
          SELECTED_IP=$IPV6
          echo -e "${GREEN}已选择 IPv6: $SELECTED_IP${NC}"
          break
        elif [ ${#OPTIONS[@]} -eq 2 ]; then
          # 只有 IPv4 和自定义选项
          while true; do
            read -p "请输入 IPv4 或 IPv6 地址: " CUSTOM_IP
            if validate_ipv4 "$CUSTOM_IP"; then
              SELECTED_IP=$CUSTOM_IP
              echo -e "${GREEN}已选择自定义 IPv4: $SELECTED_IP${NC}"
              break 2
            elif validate_ipv6 "$CUSTOM_IP"; then
              SELECTED_IP=$CUSTOM_IP
              echo -e "${GREEN}已选择自定义 IPv6: $SELECTED_IP${NC}"
              break 2
            else
              echo -e "${RED}IP 地址格式无效，请重新输入${NC}"
            fi
          done
        else
          echo -e "${RED}无效选项${NC}"
        fi
        ;;
      3)
        if [ ${#OPTIONS[@]} -eq 3 ]; then
          while true; do
            read -p "请输入 IPv4 或 IPv6 地址: " CUSTOM_IP
            if validate_ipv4 "$CUSTOM_IP"; then
              SELECTED_IP=$CUSTOM_IP
              echo -e "${GREEN}已选择自定义 IPv4: $SELECTED_IP${NC}"
              break 2
            elif validate_ipv6 "$CUSTOM_IP"; then
              SELECTED_IP=$CUSTOM_IP
              echo -e "${GREEN}已选择自定义 IPv6: $SELECTED_IP${NC}"
              break 2
            else
              echo -e "${RED}IP 地址格式无效，请重新输入${NC}"
            fi
          done
        else
          echo -e "${RED}无效选项${NC}"
        fi
        ;;
      *)
        echo -e "${RED}无效选项${NC}"
        ;;
    esac
  done
}

# 获取 Cloudflare API 和域名信息
get_cloudflare_info() {
  echo -e "${BLUE}请输入 Cloudflare API 信息:${NC}"

  while [ -z "$CF_API_TOKEN" ]; do
    read -p "API Token: " CF_API_TOKEN_INPUT
    if [ -z "$CF_API_TOKEN_INPUT" ]; then
      echo -e "${RED}API Token 不能为空${NC}"
    else
      CF_API_TOKEN="$CF_API_TOKEN_INPUT"
    fi
  done

  while [ -z "$DOMAIN_NAME" ]; do
    read -p "域名 (例如: hubproxy.example.com): " DOMAIN_NAME_INPUT
    if [ -z "$DOMAIN_NAME_INPUT" ]; then
      echo -e "${RED}域名不能为空${NC}"
    else
      DOMAIN_NAME="$DOMAIN_NAME_INPUT"
    fi
  done
}

# 获取 Cloudflare Zone ID 信息
get_cloudflare_zone_id() {
  if [ "$FETCH_TOOL" == "curl" ]; then
    CF_ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN_NAME#*.}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" | jq -r '.result[0].id')
  else
    CF_ZONE_ID=$(wget -qO - \
      --header="Authorization: Bearer ${CF_API_TOKEN}" \
      --header="Content-Type: application/json" \
      "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN_NAME#*.}" | jq -r '.result[0].id')
  fi
}

# 创建 DNS 记录（不启用代理）
create_dns_record_without_proxy() {
  echo -e "${BLUE}正在创建 DNS 记录（不启用代理）...${NC}"

  # 判断是 A 记录还是 AAAA 记录
  RECORD_TYPE="A"
  if validate_ipv6 "$SELECTED_IP"; then
    RECORD_TYPE="AAAA"
  fi

  # 获取 Cloudflare 域名 ID
  grep -q '^$' <<< "${CF_ZONE_ID}" && get_cloudflare_zone_id

  # 首先检查是否已存在同名记录
  echo -e "${BLUE}检查是否已存在同名 DNS 记录...${NC}"
  if [ "$FETCH_TOOL" == "curl" ]; then
    LIST_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?name=${DOMAIN_NAME}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json")
  else
    # 使用 wget 发送 GET 请求
    LIST_RESPONSE=$(wget -q \
      --header="Authorization: Bearer ${CF_API_TOKEN}" \
      --header="Content-Type: application/json" \
      -O - \
      "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?name=${DOMAIN_NAME}")
  fi

  # 检查API响应是否有效
  if [ -z "$LIST_RESPONSE" ]; then
    echo -e "${RED}无法从Cloudflare API获取响应，请检查网络连接和API凭证${NC}"
    exit 1
  fi

  # 验证响应是否为有效的JSON
  if ! echo "$LIST_RESPONSE" | jq empty 2>/dev/null; then
    echo -e "${RED}收到无效的API响应${NC}"
    echo -e "${YELLOW}原始响应内容: $LIST_RESPONSE${NC}"
    exit 1
  fi

  # 检查是否有现有记录
  RECORD_COUNT=$(echo "$LIST_RESPONSE" | jq -r '.result|length')

  # 如果有现有记录，则更新第一条记录
  if [ "$RECORD_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}检测到已存在 DNS 记录，将更新现有记录...${NC}"
    RECORD_ID=$(echo "$LIST_RESPONSE" | jq -r '.result[0].id')

    # 更新现有记录
    if [ "$FETCH_TOOL" == "curl" ]; then
      RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{
          "type": "'${RECORD_TYPE}'",
          "name": "'${DOMAIN_NAME}'",
          "content": "'${SELECTED_IP}'",
          "ttl": 3600,
          "proxied": false,
          "comment": "hubproxy project"
        }')
    else
      # 使用 wget 发送 PUT 请求更新记录
      RESPONSE=$(wget --method=PUT \
      --header="Authorization: Bearer ${CF_API_TOKEN}" \
      --header="Content-Type: application/json" \
      --body-data='{
        "type": "'"${RECORD_TYPE}"'",
        "name": "'"${DOMAIN_NAME}"'",
        "content": "'"${SELECTED_IP}"'",
        "ttl": 3600,
        "proxied": false,
        "comment": "hubproxy project"
      }' \
      -qO - \
      "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}")
    fi
  else
    # 没有现有记录，创建新记录
    echo -e "${BLUE}未检测到现有 DNS 记录，将创建新记录...${NC}"
    if [ "$FETCH_TOOL" == "curl" ]; then
      RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{
          "type": "'${RECORD_TYPE}'",
          "name": "'${DOMAIN_NAME}'",
          "content": "'${SELECTED_IP}'",
          "ttl": 3600,
          "proxied": false,
          "comment": "hubproxy project"
        }')
    else
      # 使用 wget 发送 POST 请求
      RESPONSE=$(wget -q \
        --header="Authorization: Bearer ${CF_API_TOKEN}" \
        --header="Content-Type: application/json" \
        --post-data='{
          "type": "'${RECORD_TYPE}'",
          "name": "'${DOMAIN_NAME}'",
          "content": "'${SELECTED_IP}'",
          "ttl": 3600,
          "proxied": false,
          "comment": "hubproxy project"
        }' \
        -O - \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records")
    fi
  fi

  # 验证响应是否有效
  if [ -z "$RESPONSE" ]; then
    echo -e "${RED}API请求无响应，请检查网络连接和API凭证${NC}"
    exit 1
  fi

  # 验证响应是否为有效的JSON
  if ! echo "$RESPONSE" | jq empty 2>/dev/null; then
    echo -e "${RED}收到无效的API响应${NC}"
    echo -e "${YELLOW}原始响应内容: $RESPONSE${NC}"
    exit 1
  fi

  SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
  if [ "$SUCCESS" = "true" ]; then
    RECORD_ID=$(echo "$RESPONSE" | jq -r '.result.id')
    echo -e "${GREEN}DNS 记录创建/更新成功，记录ID: $RECORD_ID${NC}"
  else
    ERRORS=$(echo "$RESPONSE" | jq -r '.errors[].message')
    echo -e "${RED}DNS 记录创建/更新失败: $ERRORS${NC}"
    exit 1
  fi
}

# 查找可用端口
find_available_port() {
echo -e "${BLUE}查找可用端口...${NC}"

# 检查端口是否可用，返回0表示可用，返回1表示被占用，返回2表示端口不在有效范围内
check_port() {
  local PORT=$1
  local NO_CHECK_USED=$2
  # 检查端口是否为数字且在有效范围内
  if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; then
  return 2  # 返回2表示端口不在有效范围内
  fi

  if ! grep -q 'no_check_used' <<< "$NO_CHECK_USED"; then
  # 检查端口是否被占用
  # 方法1: 使用 nc 命令
  if command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
    return 1  # 返回1表示端口被占用
    fi
  # 方法2: 使用 lsof 命令
  elif command -v lsof >/dev/null 2>&1; then
    lsof -i:"$PORT" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
    return 1  # 返回1表示端口被占用
    fi
  # 方法3: 使用 netstat 命令
  elif command -v netstat >/dev/null 2>&1; then
    netstat -nltup 2>/dev/null | grep -q ":$PORT "
    if [ $? -eq 0 ]; then
    return 1  # 返回1表示端口被占用
    fi
  # 方法4: 使用 ss 命令
  elif command -v ss >/dev/null 2>&1; then
    ss -nltup 2>/dev/null | grep -q ":$PORT "
    if [ $? -eq 0 ]; then
    return 1  # 返回1表示端口被占用
    fi
  # 方法5: 尝试使用/dev/tcp检查
  else
    (echo >/dev/tcp/127.0.0.1/"$PORT") >/dev/null 2>&1
    if [ $? -eq 0 ]; then
    return 1  # 返回1表示端口被占用
    fi
  fi

  return 0  # 返回0表示端口可用
  fi
}

# 首先检查默认端口 5000 是否可用
check_port 5000
local port_status=$?

if [ $port_status -eq 1 ]; then
  echo -e "${YELLOW}默认端口 5000 已被占用，正在查找其他端口...${NC}"

  # 随机生成端口并检查是否可用
  for i in {1..50}; do
  PORT=$((RANDOM % (65535-1024) + 1024))
  check_port $PORT "no_check_used"
  if [ $? -eq 0 ]; then
    HUBPROXY_PORT=$PORT
    echo -e "${GREEN}找到可用端口: $HUBPROXY_PORT${NC}"
    return
  fi
  done

  echo -e "${RED}无法找到可用端口${NC}"
  exit 1
elif [ $port_status -eq 2 ]; then
  echo -e "${RED}端口 5000 不在有效范围内${NC}"
  exit 1
else
  HUBPROXY_PORT=5000
  echo -e "${GREEN}使用默认端口: $HUBPROXY_PORT${NC}"
fi
}

# 创建 Docker Compose 文件
create_docker_compose_files() {
  echo -e "${BLUE}创建 Docker Compose 文件...${NC}"

  # 创建工作目录
  HUBPROXY_DIR="/root/hubproxy"
  mkdir -p "${HUBPROXY_DIR}"/conf
  mkdir -p "${HUBPROXY_DIR}"/site
  mkdir -p "${HUBPROXY_DIR}"/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory
  mkdir -p "${HUBPROXY_DIR}"/config

  # 创建 Caddyfile
  cat > "${HUBPROXY_DIR}"/conf/Caddyfile << EOF
http://${DOMAIN_NAME}, https://${DOMAIN_NAME} {
  reverse_proxy hubproxy:5000 {
    header_up X-Forwarded-For {http.request.header.CF-Connecting-IP}
    header_up X-Real-IP {http.request.header.CF-Connecting-IP}
    header_up X-Forwarded-Proto {scheme}
    header_up X-Forwarded-Host {host}
  }
}
EOF

  # 创建 docker-compose.yml
  cat > "${HUBPROXY_DIR}"/docker-compose.yml << EOF
services:
  caddy:
    image: caddy:latest
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./conf/Caddyfile:/etc/caddy/Caddyfile
      - ./site:/srv
      - ./data:/data
      - ./config:/config
    networks:
      - hubproxy_network

  hubproxy:
    image: ghcr.io/sky22333/hubproxy
    container_name: hubproxy
    restart: always
    expose:
      - "5000"  # 仅容器内可访问
    environment:
      - PORT=5000
    networks:
      - hubproxy_network

volumes:
  caddy_data:
  caddy_config:

networks:
  hubproxy_network:
    name: hubproxy_network
    driver: bridge
EOF

  echo -e "${GREEN}Docker Compose 文件创建完成${NC}"
}

# 启动 Docker Compose
start_docker_compose() {
  echo -e "${BLUE}启动 Docker Compose...${NC}"

  HUBPROXY_DIR="/root/hubproxy"
  cd "${HUBPROXY_DIR}"

  # 启动服务
  docker compose up -d

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Docker Compose 启动成功${NC}"
  else
    echo -e "${RED}Docker Compose 启动失败${NC}"
    exit 1
  fi
}

# 等待 Caddy 生成证书
wait_for_caddy_certificates() {
  echo -e "${BLUE}等待 Caddy 生成证书...${NC}"
  echo -e "${YELLOW}这可能需要几分钟时间${NC}"

  # 等待最多100秒
  for i in {1..5}; do
    sleep 5

    # 检查证书是否存在
    if [ -d "/root/hubproxy/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory" ] && [ -n "$(find /root/hubproxy/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory -name "*.crt" 2>/dev/null)" ]; then
      echo -e "${GREEN}证书已生成${NC}"
      return 0
    fi

    echo -e "${BLUE}等待中... (${i}/5)${NC}"
  done

  echo -e "${YELLOW}证书可能仍在生成中，继续执行下一步${NC}"
}

# 卸载 VPS 方案
uninstall_vps() {
  echo -e "${BLUE}开始卸载 HubProxy (VPS方案)...${NC}"

  # 停止并禁用 HubProxy 服务
  if systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null; then
    echo -e "${BLUE}停止 HubProxy 服务...${NC}"
    systemctl stop ${SERVICE_NAME}
  fi

  if systemctl is-enabled --quiet ${SERVICE_NAME} 2>/dev/null; then
    echo -e "${BLUE}禁用 HubProxy 服务...${NC}"
    systemctl disable ${SERVICE_NAME}
  fi

  # 删除 systemd 服务文件
  if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    echo -e "${BLUE}删除 systemd 服务文件...${NC}"
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
  fi

  # 删除安装目录
  if [ -d "${INSTALL_DIR}" ]; then
    echo -e "${BLUE}删除安装目录...${NC}"
    rm -rf "${INSTALL_DIR}"
  fi

  # 删除日志目录
  if [ -d "${LOG_DIR}" ]; then
    echo -e "${BLUE}删除日志目录...${NC}"
    rm -rf "${LOG_DIR}"
  fi

  # 删除临时目录
  if [ -d "${TEMP_DIR}" ]; then
    echo -e "${BLUE}删除临时目录...${NC}"
    rm -rf "${TEMP_DIR}"
  fi

  # 询问是否卸载 Caddy
  echo -e "${BLUE}是否卸载 Caddy? (y/N, 默认为N): ${NC}"
  read -r UNINSTALL_CADDY
  if [[ "${UNINSTALL_CADDY}" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}卸载 Caddy...${NC}"
    detect_os
    
    if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ] || [ "$OS" == "raspbian" ]; then
      apt remove -y caddy &>/dev/null
      rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
      rm -f /etc/apt/sources.list.d/caddy-stable.list
    elif [ "$OS" == "fedora" ]; then
      dnf remove -y caddy &>/dev/null
      dnf copr disable -y @caddy/caddy &>/dev/null
    elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
      if [ "$OS_VERSION" == "7" ]; then
        yum remove -y caddy &>/dev/null
        yum copr disable -y @caddy/caddy &>/dev/null
      else
        dnf remove -y caddy &>/dev/null
        dnf copr disable -y @caddy/caddy &>/dev/null
      fi
    elif [ "$OS" == "arch" ] || [ "$OS" == "manjaro" ] || [ "$OS" == "parabola" ]; then
      pacman -R --noconfirm caddy &>/dev/null
    fi
    
    # 删除 Caddy 配置文件
    rm -f "$CADDYFILE"
    rm -rf /etc/caddy
    rm -rf /var/lib/caddy
    
    echo -e "${GREEN}Caddy 卸载完成${NC}"
  else
    echo -e "${GREEN}跳过 Caddy 卸载${NC}"
  fi

  echo -e "${GREEN}VPS 方案卸载完成${NC}"
}

# 卸载 Docker 方案
uninstall_docker() {
  echo -e "${BLUE}开始卸载 HubProxy (Docker方案)...${NC}"

  HUBPROXY_DIR="/root/hubproxy"

  # 检查是否存在 docker-compose.yml 文件
  if [ -f "${HUBPROXY_DIR}/docker-compose.yml" ]; then
    echo -e "${BLUE}停止并删除 Docker 容器...${NC}"
    cd "${HUBPROXY_DIR}"
    docker compose down

    # 删除所有相关镜像
    echo -e "${BLUE}删除相关 Docker 镜像...${NC}"
    docker rmi caddy:latest ghcr.io/sky22333/hubproxy 2>/dev/null || true
  fi

  # 删除 hubproxy 网络（如果存在）
  if docker network ls | grep -q hubproxy_network; then
    echo -e "${BLUE}删除 hubproxy 网络...${NC}"
    docker network rm hubproxy_network 2>/dev/null || true
  fi

  # 删除映射目录
  if [ -d "${HUBPROXY_DIR}" ]; then
    echo -e "${BLUE}删除映射目录...${NC}"
    rm -rf "${HUBPROXY_DIR}"
  fi

  echo -e "${GREEN}Docker 方案卸载完成${NC}"
}

# 配置 HubProxy 端口
configure_hubproxy_port() {
  CONFIG_PATH="${INSTALL_DIR}/${CONFIG_FILE}"
  if [ -f "$CONFIG_PATH" ]; then
    echo -e "${BLUE}配置 HubProxy 端口为 $HUBPROXY_PORT${NC}"
    sed -i "s/port = .*/port = $HUBPROXY_PORT/" "$CONFIG_PATH"
    systemctl restart ${SERVICE_NAME}
    echo -e "${GREEN}HubProxy 配置更新完成${NC}"
  else
    echo -e "${RED}未找到配置文件: $CONFIG_PATH${NC}"
    exit 1
  fi
}

# 配置 Caddy 反向代理
configure_caddy_reverse_proxy() {
  echo -e "${BLUE}配置 Caddy 反向代理...${NC}"

  # 检查 Caddyfile 是否存在
  if [ ! -f "$CADDYFILE" ]; then
    echo -e "${YELLOW}Caddyfile 不存在，创建新文件${NC}"
    touch "$CADDYFILE"
  fi

  # 添加反向代理配置
  cat >> "$CADDYFILE" << EOF

http://${DOMAIN_NAME}, https://${DOMAIN_NAME} {
  reverse_proxy localhost:${HUBPROXY_PORT} {
    header_up X-Forwarded-For {http.request.header.CF-Connecting-IP}
    header_up X-Real-IP {http.request.header.CF-Connecting-IP}
    header_up X-Forwarded-Proto {scheme}
    header_up X-Forwarded-Host {host}
  }
}
EOF

  # 格式化并重新加载 Caddy 配置
  caddy fmt --overwrite "$CADDYFILE" &>/dev/null
  caddy reload --config "$CADDYFILE" &>/dev/null

  echo -e "${GREEN}Caddy 反向代理配置完成${NC}"
}

# 启用 Cloudflare 代理模式
enable_cloudflare_proxy() {
  echo -e "${BLUE}启用 Cloudflare 代理模式...${NC}"

  # 获取 Cloudflare 域名 ID
  grep -q '^$' <<< "${CF_ZONE_ID}" && get_cloudflare_zone_id

  # 获取 DNS 记录 ID
  if [ "$FETCH_TOOL" == "curl" ]; then
    RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?name=${DOMAIN_NAME}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json")
  else
    # 使用 wget 发送 GET 请求
    RESPONSE=$(wget -q \
      --header="Authorization: Bearer ${CF_API_TOKEN}" \
      --header="Content-Type: application/json" \
      -O - \
      "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?name=${DOMAIN_NAME}")
  fi

  # 验证响应是否有效
  if [ -z "$RESPONSE" ]; then
    echo -e "${RED}API请求无响应，请检查网络连接和API凭证${NC}"
    exit 1
  fi

  # 验证响应是否为有效的JSON
  if ! echo "$RESPONSE" | jq empty 2>/dev/null; then
    echo -e "${RED}收到无效的API响应${NC}"
    echo -e "${YELLOW}原始响应内容: $RESPONSE${NC}"
    exit 1
  fi

  # 解析JSON数据
  RECORD_ID=$(echo "$RESPONSE" | jq -r '.result[0].id')
  RECORD_TYPE=$(echo "$RESPONSE" | jq -r '.result[0].type')
  RECORD_NAME=$(echo "$RESPONSE" | jq -r '.result[0].name')
  RECORD_CONTENT=$(echo "$RESPONSE" | jq -r '.result[0].content')
  RECORD_TTL=$(echo "$RESPONSE" | jq -r '.result[0].ttl')

  # 验证是否成功获取记录ID
  if [ "$RECORD_ID" = "null" ] || [ -z "$RECORD_ID" ]; then
    echo -e "${RED}无法获取 DNS 记录 ID${NC}"
    echo -e "${YELLOW}原始响应内容: $RESPONSE${NC}"
    exit 1
  fi

  # 验证记录类型
  if [ "$RECORD_TYPE" != "A" ] && [ "$RECORD_TYPE" != "AAAA" ]; then
    echo -e "${RED}不支持的 DNS 记录类型: $RECORD_TYPE${NC}"
    exit 1
  fi

  # 启用代理模式
  if [ "$FETCH_TOOL" == "curl" ]; then
    RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data '{
        "type": "'${RECORD_TYPE}'",
        "name": "'${RECORD_NAME}'",
        "content": "'${RECORD_CONTENT}'",
        "ttl": '${RECORD_TTL}',
        "proxied": true,
        "comment": "hubproxy project"
      }')
  else
    # 使用 wget 发送 PUT 请求
    RESPONSE=$(wget --method=PUT \
    --header="Authorization: Bearer ${CF_API_TOKEN}" \
    --header="Content-Type: application/json" \
    --body-data='{
      "type": "'"${RECORD_TYPE}"'",
      "name": "'"${DOMAIN_NAME}"'",
      "content": "'"${SELECTED_IP}"'",
      "ttl": 3600,
      "proxied": true,
      "comment": "hubproxy project"
    }' \
    -qO - \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}")
  fi

  # 验证更新后的响应
  if [ -z "$RESPONSE" ]; then
    echo -e "${RED}API请求无响应，请检查网络连接和API凭证${NC}"
    exit 1
  fi

  if ! echo "$RESPONSE" | jq empty 2>/dev/null; then
    echo -e "${RED}更新 DNS 记录失败，收到无效的API响应${NC}"
    echo -e "${YELLOW}原始响应内容: $RESPONSE${NC}"
    exit 1
  fi

  SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
  if [ "$SUCCESS" = "true" ]; then
    echo -e "${GREEN}Cloudflare 代理模式已启用${NC}"
  else
    ERRORS=$(echo "$RESPONSE" | jq -r '.errors[].message')
    echo -e "${RED}启用 Cloudflare 代理模式失败: $ERRORS${NC}"
  fi
}

# 主程序执行流程
main() {
  # 选择安装方案
  select_installation_method

  if [ "$OPERATION" = "uninstall" ]; then
    # 执行卸载操作
    if [ "$INSTALL_TYPE" = "vps" ]; then
      uninstall_vps
    else
      uninstall_docker
    fi
    exit 0
  fi

  # 1. 安装系统依赖（包括 jq 等）
  install_system_dependencies

  # 2. 获取 Cloudflare API 信息
  get_cloudflare_info

  # 3. 获取 IP 地址
  get_ip_addresses

  # 4. 选择 IP 地址
  select_ip_address

  if [ "$INSTALL_TYPE" = "vps" ]; then
    # VPS方案
    # 5. 创建 DNS 记录（不启用代理）
    create_dns_record_without_proxy

    # 6. 安装 Caddy（如果未安装）
    install_caddy

    # 7. 安装 HubProxy
    install_hubproxy

    # 8. 查找可用端口
    find_available_port

    # 9. 配置 HubProxy 端口
    configure_hubproxy_port

    # 10. 配置 Caddy 反向代理
    configure_caddy_reverse_proxy

    # 11. 启用 Cloudflare 代理模式（在 Caddy 重新加载之后）
    enable_cloudflare_proxy
  else
    # Docker方案
    # 5. 安装 Docker（如果未安装）
    install_docker

    # 6. 创建 DNS 记录（不启用代理）
    create_dns_record_without_proxy

    # 7. 创建工作目录
    create_docker_compose_files

    # 8. 启动 Docker Compose
    start_docker_compose

    # 9. 等待 Caddy 生成证书
    wait_for_caddy_certificates

    # 10. 启用 Cloudflare 代理模式
    enable_cloudflare_proxy
  fi

  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}安装和配置已完成！${NC}"
  echo -e "${GREEN}您的 HubProxy 已通过以下地址访问:${NC}"
  echo -e "${GREEN}https://${DOMAIN_NAME}${NC}"
  echo -e "${GREEN}========================================${NC}"
}

# 执行主程序
main