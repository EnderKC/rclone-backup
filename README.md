# 自动备份任务脚本 | Automated Backup Script

<div align="center">

![Version](https://img.shields.io/badge/version-3.0-blue.svg)
![Shell](https://img.shields.io/badge/shell-bash-89E051.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

[English](#english) | [中文](#chinese)

</div>

---

<a id="chinese"></a>

## 中文说明

### 项目简介

这是一个功能强大的自动备份脚本，支持本地备份和远程存储备份，提供了直观的交互式界面和丰富的配置选项。

### 主要特性

- 🔄 支持多种备份模式
  - 挂载模式：将远程存储挂载到本地后备份
  - 直传模式：直接传输到远程存储
- 📁 灵活的路径配置
  - 支持多个备份源路径
  - 自定义目标路径映射
  - 文件排除规则
- 🕒 计划任务管理
  - 支持每日/每周/每月定时备份
  - 自定义 cron 表达式
- 📊 完善的日志系统
  - 详细的备份记录
  - 自动日志清理
  - 错误追踪
- 🔧 便捷的配置管理
  - 交互式配置向导
  - 实时配置修改
  - 配置文件备份
- 🌐 远程存储集成
  - 完整的 rclone 支持
  - 多种云存储服务支持
  - 自动认证管理

### 安装说明

1. 克隆仓库：
```bash
git clone <repository_url>
cd <repository_name>
```

2. 添加执行权限：
```bash
chmod +x backup_script.sh
```

3. 运行配置向导：
```bash
sudo ./backup_script.sh
```

### 使用方法

1. 交互式菜单：
   - 运行脚本进入主菜单
   - 按照提示进行操作

2. 命令行模式：
```bash
sudo ./backup_script.sh main  # 直接执行备份任务
```

### 配置说明

主要配置项包括：
- `BACKUP_PATHS`：备份路径映射
- `EXCLUDE_PATTERNS`：排除规则
- `DEST_ROOT`：目标根目录
- `RCLONE_REMOTE`：远程存储配置
- `LOG_DIR`：日志目录
- `MAX_LOG_DAYS`：日志保留天数

---

<a id="english"></a>

## English Description

### Project Overview

This is a powerful automated backup script that supports both local and remote storage backups, providing an intuitive interactive interface and rich configuration options.

### Key Features

- 🔄 Multiple Backup Modes
  - Mount Mode: Backup after mounting remote storage locally
  - Direct Mode: Transfer directly to remote storage
- 📁 Flexible Path Configuration
  - Support for multiple backup source paths
  - Custom target path mapping
  - File exclusion rules
- 🕒 Schedule Management
  - Daily/Weekly/Monthly scheduled backups
  - Custom cron expressions
- 📊 Comprehensive Logging
  - Detailed backup records
  - Automatic log cleanup
  - Error tracking
- 🔧 Easy Configuration
  - Interactive setup wizard
  - Real-time configuration updates
  - Configuration backup
- 🌐 Remote Storage Integration
  - Full rclone support
  - Multiple cloud storage services
  - Automatic authentication management

### Installation

1. Clone repository:
```bash
git clone <repository_url>
cd <repository_name>
```

2. Add execution permission:
```bash
chmod +x backup_script.sh
```

3. Run setup wizard:
```bash
sudo ./backup_script.sh
```

### Usage

1. Interactive Menu:
   - Run script to enter main menu
   - Follow the prompts

2. Command Line Mode:
```bash
sudo ./backup_script.sh main  # Execute backup task directly
```

### Configuration

Main configuration items include:
- `BACKUP_PATHS`: Backup path mapping
- `EXCLUDE_PATTERNS`: Exclusion rules
- `DEST_ROOT`: Destination root directory
- `RCLONE_REMOTE`: Remote storage configuration
- `LOG_DIR`: Log directory
- `MAX_LOG_DAYS`: Log retention period

---

## License

MIT License © 2024
