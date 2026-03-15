# Kiro Gateway — systemd 服务部署指南

本文档说明如何将 Kiro Gateway 部署为 systemd 系统服务，实现**开机自启**和**崩溃自动重启**。

## 前置条件

- Ubuntu / Debian 等支持 systemd 的 Linux 发行版
- Python 3.10+（当前使用 `/home/hxd/miniconda3/bin/python`）
- 已配置 `.env` 文件（从 `.env.example` 复制并填入凭据）

## 相关文件

| 文件 | 说明 |
|------|------|
| `setup-service.sh` | 一键安装/卸载/管理脚本 |
| `kiro-gateway.service` | systemd 服务单元文件 |
| `.env` | 运行时环境变量配置 |

## 快速开始

### 1. 配置环境变量

如果还没有 `.env` 文件，先从模板复制：

```bash
cp .env.example .env
```

编辑 `.env`，至少设置以下两项：

```ini
PROXY_API_KEY="你的自定义密码"
REFRESH_TOKEN="你的 Kiro 刷新令牌"
```

### 2. 安装服务

```bash
sudo ./setup-service.sh install
```

脚本会自动完成以下操作：

1. 检查 Python、依赖包、`.env` 文件是否就绪
2. 缺少的 pip 依赖会自动安装
3. 创建 `debug_logs/` 目录
4. 将服务文件复制到 `/etc/systemd/system/`
5. 启用开机自启并立即启动服务
6. 验证服务是否正常运行

## 服务管理

### 使用管理脚本

```bash
sudo ./setup-service.sh install     # 安装并启动服务
sudo ./setup-service.sh uninstall   # 停止并卸载服务
sudo ./setup-service.sh status      # 查看运行状态
sudo ./setup-service.sh logs        # 实时查看日志（Ctrl+C 退出）
sudo ./setup-service.sh restart     # 重启服务
```

### 使用 systemctl

```bash
sudo systemctl start   kiro-gateway   # 启动
sudo systemctl stop    kiro-gateway   # 停止
sudo systemctl restart kiro-gateway   # 重启
sudo systemctl status  kiro-gateway   # 查看状态
sudo systemctl enable  kiro-gateway   # 启用开机自启
sudo systemctl disable kiro-gateway   # 禁用开机自启
```

## 日志位置

Kiro Gateway 的日志分为两类：**系统日志**和**调试日志**。

### 系统日志（journald）

服务的所有标准输出和错误输出都通过 systemd 的 journald 管理，是查看日志的**主要方式**。

```bash
# 查看全部日志
journalctl -u kiro-gateway

# 实时跟踪日志（类似 tail -f）
journalctl -u kiro-gateway -f

# 只看今天的日志
journalctl -u kiro-gateway --since today

# 查看最近 100 行
journalctl -u kiro-gateway -n 100

# 查看最近 1 小时内的日志
journalctl -u kiro-gateway --since "1 hour ago"

# 查看指定时间范围
journalctl -u kiro-gateway --since "2026-03-13 08:00" --until "2026-03-13 12:00"

# 只看错误级别以上
journalctl -u kiro-gateway -p err

# 导出日志到文件
journalctl -u kiro-gateway --since today --no-pager > /tmp/kiro-today.log
```

> journald 日志由系统自动轮转和清理，无需手动维护。默认保留策略取决于 `/etc/systemd/journald.conf` 的配置（通常按磁盘占比或时间自动清理）。

### 调试日志（文件）

当 `.env` 中开启 `DEBUG_MODE` 时，详细的请求/响应日志会写入本地文件：

```
项目目录/debug_logs/
```

通过 `.env` 控制调试日志行为：

```ini
# off   — 不记录调试日志（默认，生产推荐）
# errors — 仅记录失败请求的完整信息
# all    — 记录所有请求的完整信息（注意磁盘空间）
DEBUG_MODE="off"

# 调试日志输出目录（默认为 debug_logs）
DEBUG_DIR="debug_logs"
```

> **安全提示**: 调试日志可能包含 Bearer Token 等敏感信息，仅在排查问题时开启，排查完毕后及时关闭。

### 日志位置速查表

| 类型 | 位置 | 用途 |
|------|------|------|
| 系统日志 | `journalctl -u kiro-gateway` | 日常监控，查看启停记录、运行状态、错误信息 |
| 实时日志 | `journalctl -u kiro-gateway -f` | 实时观察请求处理情况 |
| 调试日志 | `./debug_logs/` | 详细的请求/响应内容（需手动开启） |

## 自动重启策略

服务配置了以下重启保护机制：

| 参数 | 值 | 说明 |
|------|-----|------|
| `Restart` | `always` | 无论退出码如何，始终自动重启 |
| `RestartSec` | `5` | 崩溃后等待 5 秒再重启 |
| `StartLimitIntervalSec` | `300` | 在 5 分钟的滑动窗口内 |
| `StartLimitBurst` | `10` | 最多允许重启 10 次 |

如果 5 分钟内重启超过 10 次，systemd 会判定服务存在严重问题并停止尝试，需要手动干预：

```bash
# 查看失败原因
sudo systemctl status kiro-gateway
journalctl -u kiro-gateway -n 50

# 修复问题后重新启动
sudo systemctl reset-failed kiro-gateway
sudo systemctl start kiro-gateway
```

## 安全加固

service 文件包含以下安全措施：

| 配置 | 说明 |
|------|------|
| `User=hxd` | 以普通用户身份运行，而非 root |
| `NoNewPrivileges=yes` | 禁止进程提升权限 |
| `ProtectSystem=strict` | 文件系统只读挂载（除显式允许的路径） |
| `ProtectHome=read-only` | 家目录只读（可读取 `.env` 和代码，但不能随意写入） |
| `ReadWritePaths=.../debug_logs` | 仅允许写入调试日志目录 |
| `PrivateTmp=yes` | 使用隔离的 /tmp 目录 |

## 修改配置后的操作

### 修改了 `.env`

```bash
sudo systemctl restart kiro-gateway
```

### 修改了 `kiro-gateway.service`

```bash
sudo cp kiro-gateway.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart kiro-gateway
```

### 更新了代码（git pull）

```bash
sudo systemctl restart kiro-gateway
```

## 卸载

```bash
sudo ./setup-service.sh uninstall
```

卸载操作会：
- 停止正在运行的服务
- 禁用开机自启
- 删除 `/etc/systemd/system/kiro-gateway.service`
- 重载 systemd 配置

> 项目文件、`.env` 和 `debug_logs/` 目录不会被删除。历史日志仍可通过 `journalctl -u kiro-gateway` 查看，直到系统自动清理。

## 故障排查

### 服务无法启动

```bash
# 查看详细错误信息
journalctl -u kiro-gateway -n 30 --no-pager

# 常见原因：
# 1. .env 文件缺失或配置错误
# 2. Python 依赖未安装 → pip install -r requirements.txt
# 3. 端口 8000 被占用 → lsof -i :8000
```

### 服务频繁重启

```bash
# 查看最近的崩溃日志
journalctl -u kiro-gateway --since "30 min ago" | grep -i "error\|traceback\|exception"

# 如果触发了重启上限
sudo systemctl reset-failed kiro-gateway
sudo systemctl start kiro-gateway
```

### 手动测试服务是否正常

```bash
# 健康检查
curl http://localhost:8000/health

# 查看可用模型
curl http://localhost:8000/v1/models \
  -H "Authorization: Bearer 你的PROXY_API_KEY"
```
