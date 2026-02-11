# MySsh

WSL SSH 服务器快速连接工具，支持模糊搜索、sshpass 连接和 WinSCP 文件管理。

## 演示

![演示截图](images/image.png)

## 安装

### 1. 安装依赖

```bash
sudo apt install sshpass fzf
```

### Windows（PowerShell）

提供 `myssh.ps1`（主脚本）和 `myssh.bat`（包装器）。依赖说明：

- 必需：Windows OpenSSH Client（Windows 10/11 可在“可选功能”里安装）
- 可选：`fzf`（用于模糊搜索，未安装则回退为编号选择）
- 可选：`MYSSH_FZF_PATH`（若 `fzf` 未在 `PATH` 中，可指定 `fzf.exe` 的完整路径）
- 可选：`MYSSH_PLINK_PATH`（若需自动输入密码登录，建议安装 PuTTY 并指定 `plink.exe` 路径）
- 可选：`WinSCP`（用于 `-w` 模式）
- 可选：`plink`（PuTTY，若你在 `servers.txt` 中保存了密码并希望自动登录）

示例：

```powershell
.\myssh.ps1
.\myssh.ps1 -l
.\myssh.ps1 -w
```

如果执行策略受限，可使用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\myssh.ps1
```

如果中文显示乱码，可在 PowerShell 中先执行：

```powershell
chcp 65001
```

并确保 `servers.txt` 为 UTF-8 编码。

### 2. 全局安装（可选）

```bash
sudo ln -sf /root/code/TermMate/scripts/myssh /usr/local/bin/myssh
```

## 配置

编辑 `servers.txt` 文件，添加服务器信息：

```
# 支持以下分隔格式（Tab或空格均可）：
标签名  服务器IP  端口  账号  密码

# 示例
生产服务器  192.168.1.100  22  root  password123
测试环境    10.0.0.50      2222  admin  test456
```

## 使用

| 命令 | 说明 |
|------|------|
| `myssh` | 交互式选择服务器并 SSH 连接 |
| `myssh -w` | 交互式选择服务器并用 WinSCP 打开 |
| `myssh -l` | 列出所有服务器 |
| `myssh -e` | 编辑服务器配置文件 |
| `myssh -h` | 显示帮助信息 |

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `MYSSH_SERVERS_FILE` | 服务器配置文件路径 | `<脚本目录>/servers.txt` |
| `MYSSH_WINSCP_PATH` | WinSCP 可执行文件路径 | `/mnt/c/Users/.../WinSCP.exe` |
