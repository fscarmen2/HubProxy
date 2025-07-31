# HubProxy
本项目是一个轻量、高性能的代理部署脚本，支持一键搭建 Docker 镜像和 GitHub 文件加速服务。集成了 Cloudflare API、Caddy 和 HubProxy，实现自动配置与快速部署。
# HubProxy 一键安装脚本

🚀 **Docker 和 GitHub 加速代理服务器一键部署脚本**

一个轻量级、高性能的多功能代理服务部署脚本，提供 Docker 镜像加速、GitHub 文件加速、下载离线镜像、在线搜索 Docker 镜像等功能的一键部署。

本项目基于 [sky22333/hubproxy](https://github.com/sky22333/hubproxy) 开发，感谢原项目作者的杰出贡献。

官方示例: https://demo.52013120.xyz/

## 📖 目录

- [📝 更新日志](#-更新日志)
- [✨ 脚本特点](#-脚本特点)
- [🎯 解决的问题](#-解决的问题)
- [📥 安装](#-安装)
- [🔐 Cloudflare API 凭据获取](#-cloudflare-api-凭据获取)
  - [获取 Zone ID](#获取-zone-id)
  - [创建 API Token](#创建-api-token)
- [⚙️ 使用方法](#️-使用方法)
  - [安装过程](#安装过程)
  - [卸载过程](#卸载过程)
- [🐳 方案说明](#-方案说明)
  - [VPS方案](#vps方案)
  - [Docker方案](#docker方案)
  - [部署及 itdog 多地 ping 截图](#部署及-itdog-多地-ping-截图)
- [🚀 HubProxy 功能说明](#-hubproxy-功能说明)
- [🔧 配置说明](#-配置说明)
- [⚠️ 免责声明](#️-免责声明)

## 📝 更新日志

- **2025-07-30 v1.0.0** 1. 全自动化HTTPS解决方案：深度整合Caddy 2反向代理与Let's Encrypt证书自动签发，实现零配置的HTTPS服务部署; 2. 双模式智能部署：支持Docker容器化与宿主机原生部署，通过环境自适应的安装脚本自动选择最优方案

## ✨ 脚本特点

- 🔄 **双方案部署** - 支持传统VPS部署和Docker容器化部署两种方案
- 🌐 **自动DNS配置** - 集成Cloudflare API，自动创建和配置DNS记录
- 🔐 **SSL证书自动申请与维护** - 集成Caddy自动申请和维护Let's Encrypt SSL证书
- 🚀 **一键部署** - 自动化安装所有依赖，配置反向代理，启用Cloudflare代理
- 🧹 **完整卸载** - 支持完全卸载已部署的方案，清理所有相关资源
- 🏗️ **系统适配** - 支持Ubuntu、Debian、CentOS、RHEL、Fedora、Arch Linux等主流系统
- 📦 **依赖管理** - 自动检测和安装所需依赖，包括curl/wget、jq、docker等
- 🌍 **IPv4/IPv6互通** - 使用Cloudflare CDN，突破 IPv4/IPv6 互通限制，即使在仅支持 IPv6 的机器上，也能成功下载来自 GitHub（IPv4-only）的文件

## 🎯 解决的问题

本脚本主要解决以下问题：

1. **复杂的手动配置** - 传统部署需要手动安装Caddy、配置反向代理、申请SSL证书、配置DNS等复杂步骤
2. **环境依赖问题** - 自动检测和安装系统依赖，避免因缺少依赖导致的部署失败
3. **SSL证书配置** - 集成Caddy自动申请和管理SSL证书，无需手动操作
4. **DNS配置繁琐** - 集成Cloudflare API，自动创建和更新DNS记录
5. **部署方案选择困难** - 提供VPS和Docker两种部署方案，满足不同用户需求
6. **卸载不彻底** - 提供完整的卸载功能，确保所有相关资源被正确清理

## 📥 安装

```
bash <(curl -sSL https://raw.githubusercontent.com/fscarmen2/hubproxy/main/script.sh)
```
或者
```
bash <(wget -qO- https://raw.githubusercontent.com/fscarmen2/hubproxy/main/script.sh)
```

## 🔐 Cloudflare API 凭据获取

### 获取 Zone ID
1. 登录 Cloudflare 控制台
2. 选择您要使用的域名
3. 在概述页面的右侧边栏中找到"API"部分
4. Zone ID 显示在域名下方

### 创建 API Token
1. 在 Cloudflare 控制台右上角点击用户头像
2. 选择"我的个人资料"
3. 点击"API Tokens"选项卡
4. 点击"创建令牌"
5. 选择"自定义令牌"
6. 配置以下权限：
   - 权限：
     - Zone - DNS - Edit
   - 区域资源：
     - 包含 - 指定区域（选择您的域名）
7. 点击"继续到摘要"
8. 点击"创建令牌"
9. 复制生成的 API Token 并保存

<img width="2874" height="1244" alt="image" src="https://github.com/user-attachments/assets/d263c020-c285-4627-8831-51424243d2f9" />

<img width="2172" height="1064" alt="image" src="https://github.com/user-attachments/assets/886ecb04-e758-4a37-aaa0-3e9f4adbf624" />

<img width="2146" height="1274" alt="image" src="https://github.com/user-attachments/assets/e6837690-7fbc-4913-8b31-b0372351932b" />

<img width="2850" height="1230" alt="image" src="https://github.com/user-attachments/assets/c911f072-f837-4658-8502-851d78dfb192" />

## ⚙️ 使用方法

### 安装过程

脚本运行后会引导用户完成以下步骤：

1. **选择部署方案** - 选择VPS方案或Docker方案
2. **输入Cloudflare信息** - 输入Zone ID、API Token和域名
3. **选择服务器IP** - 从检测到的IP地址中选择或输入自定义IP
4. **自动部署** - 脚本会自动完成以下操作：
   - 安装系统依赖
   - 创建DNS记录
   - 安装和配置Caddy
   - 部署HubProxy服务
   - 配置反向代理
   - 启用Cloudflare代理
   - 等待SSL证书生成

### 卸载过程

脚本支持完全卸载已部署的方案：

1. **选择卸载操作** - 在脚本菜单中选择卸载选项
2. **自动检测已部署方案** - 脚本会自动检测已部署的方案
3. **执行卸载** - 根据检测到的方案执行相应的卸载操作：
   - **VPS方案卸载**：停止并禁用服务，删除安装目录和配置文件
   - **Docker方案卸载**：停止并删除容器，删除相关镜像和映射目录

## 🐳 方案说明

### VPS方案

VPS方案将HubProxy作为系统服务直接部署在服务器上：

- HubProxy以systemd服务方式运行
- Caddy作为反向代理和SSL证书管理器
- 配置文件位于`/opt/hubproxy/config.toml`
- 日志文件位于`/var/log/hubproxy/`
- 服务名称：`hubproxy`

### Docker方案

Docker方案使用Docker Compose部署HubProxy和Caddy：

- 使用官方HubProxy镜像：`ghcr.io/sky22333/hubproxy`
- 使用官方Caddy镜像：`caddy:latest`
- 所有配置和数据映射到`/root/hubproxy/`目录
- 自动创建Docker网络实现容器间通信
- SSL证书存储在`/root/hubproxy/data/caddy/certificates/`目录

### 部署及 itdog 多地 ping 截图

<img width="1744" height="1340" alt="image" src="https://github.com/user-attachments/assets/b0a204fb-d4f1-423e-8e53-a21aaccf592c" />

<img width="566" height="151" alt="image" src="https://github.com/user-attachments/assets/29e02454-7aa6-4ae2-bf64-b5fd6e43ad41" />

<img width="2030" height="1424" alt="image" src="https://github.com/user-attachments/assets/89c51128-68bc-4442-8ed8-ea261646f822" />

<img width="1996" height="1378" alt="image" src="https://github.com/user-attachments/assets/d609463c-d218-4c6f-867a-5554dec4fd0d" />

## 🚀 HubProxy 功能说明

- 🐳 **Docker 镜像加速** - 单域名实现 Docker Hub、GHCR、Quay 等多个镜像仓库加速，流式传输优化拉取速度。
- 🐳 **离线镜像包** - 支持下载离线镜像包，流式传输加防抖设计。
- 📁 **GitHub 文件加速** - 加速 GitHub Release、Raw 文件下载，支持`api.github.com`，脚本嵌套加速等等
- 🤖 **AI 模型库支持** - 支持 Hugging Face 模型下载加速
- 🛡️ **智能限流** - IP 限流保护，防止滥用
- 🚫 **仓库审计** - 强大的自定义黑名单，白名单，同时审计镜像仓库，和GitHub仓库
- 🔍 **镜像搜索** - 在线搜索 Docker 镜像
- ⚡ **轻量高效** - 基于 Go 语言，单二进制文件运行，资源占用低，优雅的内存清理机制。
- 🔧 **统一配置** - 统一配置管理

## 🔧 配置说明

脚本会自动配置大部分参数，用户只需提供以下信息：

1. **Cloudflare Zone ID** - 在Cloudflare仪表板的域名设置中找到
2. **Cloudflare API Token** - 具有DNS记录编辑权限的API令牌
3. **域名** - 用于访问HubProxy服务的域名

## ⚠️ 免责声明

- 本程序仅供学习交流使用，请勿用于非法用途
- 使用本程序需遵守当地法律法规
- 作者不对使用者的任何行为承担责任
- 脚本按"现状"提供，不提供任何担保

---

<div align="center">

**⭐ 如果这个项目对你有帮助，请给个 Star！⭐**

</div>