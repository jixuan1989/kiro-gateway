#!/usr/bin/env bash
# ============================================================
# Kiro Gateway — systemd 服务安装/管理脚本
# 用法:
#   ./setup-service.sh install    安装并启动服务（开机自启+崩溃自重启）
#   ./setup-service.sh uninstall  停止并移除服务
#   ./setup-service.sh status     查看服务状态
#   ./setup-service.sh logs       实时查看日志
#   ./setup-service.sh restart    重启服务
# ============================================================

set -euo pipefail

# -------- 配置 --------
SERVICE_NAME="kiro-gateway"
SERVICE_FILE="${SERVICE_NAME}.service"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYSTEMD_DIR="/etc/systemd/system"

# -------- 颜色 --------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }
title() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# -------- 前置检查 --------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本需要 root 权限，请使用 sudo 运行"
        echo "  sudo $0 $*"
        exit 1
    fi
}

check_prerequisites() {
    title "检查前置条件"

    # 检查 systemd
    if ! command -v systemctl &>/dev/null; then
        error "系统不支持 systemd"
        exit 1
    fi
    info "systemd 可用"

    # 检查 service 文件
    if [[ ! -f "${PROJECT_DIR}/${SERVICE_FILE}" ]]; then
        error "找不到 ${SERVICE_FILE}，请确保在项目根目录运行"
        exit 1
    fi
    info "服务配置文件存在"

    # 检查 .env 文件
    if [[ ! -f "${PROJECT_DIR}/.env" ]]; then
        warn ".env 文件不存在，请从 .env.example 复制并配置"
        echo "  cp ${PROJECT_DIR}/.env.example ${PROJECT_DIR}/.env"
        echo "  编辑 .env 设置你的 REFRESH_TOKEN 和 PROXY_API_KEY"
        exit 1
    fi
    info ".env 配置文件存在"

    # 检查 Python
    local python_path
    python_path=$(grep "^ExecStart=" "${PROJECT_DIR}/${SERVICE_FILE}" | sed 's/ExecStart=//' | awk '{print $1}')
    if [[ ! -x "${python_path}" ]]; then
        error "Python 不存在或不可执行: ${python_path}"
        exit 1
    fi
    info "Python 可用: ${python_path}"

    # 检查 main.py
    if [[ ! -f "${PROJECT_DIR}/main.py" ]]; then
        error "找不到 main.py"
        exit 1
    fi
    info "main.py 存在"

    # 检查依赖
    if ! "${python_path}" -c "import fastapi, uvicorn, httpx" 2>/dev/null; then
        warn "Python 依赖未完全安装，正在安装..."
        "${python_path}" -m pip install -r "${PROJECT_DIR}/requirements.txt" --quiet
        info "依赖安装完成"
    else
        info "Python 依赖已就绪"
    fi
}

# -------- 安装 --------
do_install() {
    check_root "$@"
    check_prerequisites

    title "安装 systemd 服务"

    # 创建 debug_logs 目录
    mkdir -p "${PROJECT_DIR}/debug_logs"
    chown "$(stat -c '%U:%G' "${PROJECT_DIR}")" "${PROJECT_DIR}/debug_logs"
    info "debug_logs 目录已就绪"

    # 复制 service 文件到 systemd 目录
    cp "${PROJECT_DIR}/${SERVICE_FILE}" "${SYSTEMD_DIR}/${SERVICE_FILE}"
    info "服务文件已复制到 ${SYSTEMD_DIR}/${SERVICE_FILE}"

    # 重载 systemd 配置
    systemctl daemon-reload
    info "systemd 配置已重载"

    # 启用开机自启
    systemctl enable "${SERVICE_NAME}"
    info "已启用开机自启"

    # 启动服务
    systemctl start "${SERVICE_NAME}"
    info "服务已启动"

    # 等待几秒检查状态
    sleep 3

    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        info "服务运行正常 ✓"
    else
        error "服务启动可能存在问题，请检查日志"
        echo ""
        journalctl -u "${SERVICE_NAME}" --no-pager -n 20
        exit 1
    fi

    title "安装完成"
    echo ""
    echo -e "  服务名称:   ${CYAN}${SERVICE_NAME}${NC}"
    echo -e "  服务状态:   ${GREEN}运行中${NC}"
    echo -e "  开机自启:   ${GREEN}已启用${NC}"
    echo -e "  崩溃重启:   ${GREEN}已启用${NC} (5秒后自动重启, 5分钟内最多10次)"
    echo ""
    echo -e "${CYAN}📋 日志位置:${NC}"
    echo -e "  系统日志:   journalctl -u ${SERVICE_NAME}       ${YELLOW}(主日志)${NC}"
    echo -e "  实时日志:   journalctl -u ${SERVICE_NAME} -f    ${YELLOW}(实时跟踪)${NC}"
    echo -e "  今日日志:   journalctl -u ${SERVICE_NAME} --since today"
    echo -e "  调试日志:   ${PROJECT_DIR}/debug_logs/          ${YELLOW}(需开启 DEBUG_MODE)${NC}"
    echo ""
    echo -e "${CYAN}📌 常用命令:${NC}"
    echo "  sudo systemctl status  ${SERVICE_NAME}    # 查看状态"
    echo "  sudo systemctl restart ${SERVICE_NAME}    # 重启服务"
    echo "  sudo systemctl stop    ${SERVICE_NAME}    # 停止服务"
    echo "  sudo $0 logs                              # 实时查看日志"
    echo "  sudo $0 uninstall                         # 卸载服务"
    echo ""
}

# -------- 卸载 --------
do_uninstall() {
    check_root "$@"

    title "卸载 systemd 服务"

    if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
        systemctl stop "${SERVICE_NAME}"
        info "服务已停止"
    fi

    if systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null; then
        systemctl disable "${SERVICE_NAME}"
        info "已禁用开机自启"
    fi

    if [[ -f "${SYSTEMD_DIR}/${SERVICE_FILE}" ]]; then
        rm -f "${SYSTEMD_DIR}/${SERVICE_FILE}"
        info "服务文件已删除"
    fi

    systemctl daemon-reload
    info "systemd 配置已重载"

    title "卸载完成"
    echo ""
    warn "注意: 项目文件、.env 和 debug_logs 未删除"
    echo "  日志仍可通过 journalctl -u ${SERVICE_NAME} 查看（直到系统清理）"
    echo ""
}

# -------- 状态 --------
do_status() {
    title "服务状态"
    systemctl status "${SERVICE_NAME}" --no-pager 2>/dev/null || warn "服务未安装或不可用"
}

# -------- 日志 --------
do_logs() {
    title "实时日志 (Ctrl+C 退出)"
    echo ""
    journalctl -u "${SERVICE_NAME}" -f --no-pager --output=short-iso
}

# -------- 重启 --------
do_restart() {
    check_root "$@"

    title "重启服务"
    systemctl restart "${SERVICE_NAME}"
    sleep 2

    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        info "服务已重启并运行正常"
    else
        error "重启失败，查看日志:"
        journalctl -u "${SERVICE_NAME}" --no-pager -n 15
    fi
}

# -------- 主入口 --------
case "${1:-}" in
    install)
        do_install "$@"
        ;;
    uninstall|remove)
        do_uninstall "$@"
        ;;
    status)
        do_status
        ;;
    logs|log)
        do_logs
        ;;
    restart)
        do_restart "$@"
        ;;
    *)
        echo "Kiro Gateway — systemd 服务管理脚本"
        echo ""
        echo "用法: sudo $0 <命令>"
        echo ""
        echo "命令:"
        echo "  install     安装服务（开机自启+崩溃自重启）"
        echo "  uninstall   停止并移除服务"
        echo "  status      查看服务状态"
        echo "  logs        实时查看日志"
        echo "  restart     重启服务"
        echo ""
        exit 1
        ;;
esac
