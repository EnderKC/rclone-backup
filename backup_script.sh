#!/bin/bash
# 交互式智能备份脚本 v3.0

# 确保在脚本开始处定义所有函数
set -e

### 颜色定义 ###
# 基础颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m'

# 高亮颜色
HRED='\033[1;31m'
HGREEN='\033[1;32m'
HYELLOW='\033[1;33m'
HBLUE='\033[1;34m'
HPURPLE='\033[1;35m'
HCYAN='\033[1;36m'
HGRAY='\033[1;37m'

### 符号定义 ###
CHECK_MARK="${GREEN}✓${NC}"
CROSS_MARK="${RED}✗${NC}"
ARROW="${BLUE}→${NC}"
BULLET="${YELLOW}•${NC}"

### 辅助函数 ###
print_status() {
    local message="$1"
    local type="${2:-info}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 终端输出使用颜色
    if [ -t 1 ]; then  # 如果是终端
        case "$type" in
            success) echo -e "${GREEN}✓ $message${NC}" ;;
            error)   echo -e "${RED}✗ $message${NC}" ;;
            warning) echo -e "${YELLOW}⚠ $message${NC}" ;;
            info)    echo -e "${BLUE}ℹ $message${NC}" ;;
        esac
    else  # 如果是日志文件
        echo "[${timestamp}] [${type^^}] $message"
    fi
}

print_header() {
    local title="$1"
    local title_len=${#title}
    local padding=$(( (BOX_WIDTH - title_len) / 2 ))
    local left_padding=$padding
    local right_padding=$padding
    
    # 如果标题长度为奇数，右边多加一个空格
    [ $(( title_len % 2 )) -eq 1 ] && right_padding=$((padding + 1))
    
    echo -e "${BLUE}.${HLINE}.${NC}"
    printf "${BLUE}|%*s%s%*s|${NC}\n" $left_padding "" "$title" $right_padding ""
    echo -e "${BLUE}|${HLINE}|${NC}"
}

print_section() {
    local title="$1"
    echo -e "${BLUE}.-${SLINE}-.${NC}"
    echo -e "${BLUE}|${NC} ${CYAN}:: $title ::${NC}"
}

print_menu_item() {
    local number="$1"
    local text="$2"
    local status="$3"
    local width=$((BOX_WIDTH - 8))  # 减去边框和编号的空间
    
    printf "${BLUE}|${NC} ${HPURPLE}%s${NC}) ${HCYAN}%-${width}s${NC}" "$number" "$text"
    if [ -n "$status" ]; then
        printf " [${HYELLOW}%s${NC}]" "$status"
    fi
    printf " ${BLUE}|${NC}\n"
}

print_info() {
    local label="$1"
    local value="$2"
    local color="${3:-$HCYAN}"
    local info_width=$((BOX_WIDTH - 20))
    
    [ "$info_width" -lt 20 ] && info_width=20
    
    printf "${BLUE}|${NC} ${HGRAY}%-15s${NC} ${BLUE}::${NC} ${color}%-*s${NC}${BLUE}|${NC}\n" \
           "$label" "$info_width" "$value"
}

### 字体检测和安装 ###
check_and_install_fonts() {
    print_status "检查字体支持..." "info"
    
    # 检查是否安装了 locales
    if ! dpkg -l | grep -q "^ii.*locales"; then
        print_status "正在安装 locales..." "info"
        sudo apt-get update >/dev/null 2>&1
        sudo apt-get install -y locales >/dev/null 2>&1
    fi

    # 确保启用了中文支持
    if ! locale -a | grep -q "zh_CN.utf8"; then
        print_status "正在配置中文支持..." "info"
        sudo locale-gen zh_CN.UTF-8 >/dev/null 2>&1
        sudo update-locale LANG=zh_CN.UTF-8 >/dev/null 2>&1
    fi

    # 检查并安装必要的字体包
    local font_packages=(
        "fonts-noto-cjk"        # Google Noto CJK 字体
        "fonts-wqy-microhei"    # 文泉驿微米黑
        "fonts-wqy-zenhei"      # 文泉驿正黑
    )

    local missing_fonts=()
    for pkg in "${font_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$pkg"; then
            missing_fonts+=("$pkg")
        fi
    done

    if [ ${#missing_fonts[@]} -ne 0 ]; then
        print_status "正在安装必要的字体包..." "info"
        sudo apt-get update >/dev/null 2>&1
        for font in "${missing_fonts[@]}"; do
            print_status "安装 $font..." "info"
            sudo apt-get install -y "$font" >/dev/null 2>&1
        done
        
        # 刷新字体缓存
        sudo fc-cache -f >/dev/null 2>&1
    fi

    # 设置正确的终端编码
    export LANG=zh_CN.UTF-8
    export LC_ALL=zh_CN.UTF-8

    # 检查终端是否支持 UTF-8
    if ! locale | grep -q "UTF-8"; then
        print_status "警告: 终端可能不支持 UTF-8，界面可能显示不正常" "warning"
        sleep 2
    fi
}

### 依赖检查 ###
check_dependencies() {
    local missing_deps=()
    
    # 检查必要的命令
    local required_commands=(
        "rclone"
        "rsync"
        "mount"
        "df"
        "date"
        "grep"
        "awk"
        "sed"
    )
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    # 如果有缺失的依赖，显示错误
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "缺少必要的依赖:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        return 1
    fi
    
    return 0
}

### 安装依赖函数 ###
install_fuse() {
    print_status "正在安装 FUSE 支持..." "info"
    
    # 检测系统类型
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/debian_version ]; then
        OS=debian
    elif [ -f /etc/redhat-release ]; then
        OS=rhel
    else
        OS=$(uname -s)
    fi

    # 根据系统类型安装
    case "${OS,,}" in
        debian|ubuntu)
            apt update -qq >/dev/null 2>&1
            if ! apt install -y fuse3 >/dev/null 2>&1; then
                print_status "尝试安装 fuse 包..." "info"
                if ! apt install -y fuse >/dev/null 2>&1; then
                    print_status "FUSE 安装失败" "error"
                    return 1
                fi
            fi
            ;;
        centos|rhel|fedora)
            if ! yum install -y fuse3 >/dev/null 2>&1; then
                print_status "尝试安装 fuse 包..." "info"
                if ! yum install -y fuse >/dev/null 2>&1; then
                    print_status "FUSE 安装失败" "error"
                    return 1
                fi
            fi
            ;;
        alpine)
            if ! apk add fuse3 >/dev/null 2>&1; then
                print_status "尝试安装 fuse 包..." "info"
                if ! apk add fuse >/dev/null 2>&1; then
                    print_status "FUSE 安装失败" "error"
                    return 1
                fi
            fi
            ;;
        *)
            print_status "未知的系统类型: $OS" "error"
            print_status "请手动安装 fuse 或 fuse3 包" "info"
            return 1
            ;;
    esac

    # 验证安装
    if command -v fusermount3 >/dev/null 2>&1 || command -v fusermount >/dev/null 2>&1; then
        print_status "FUSE 安装成功" "success"
        return 0
    else
        print_status "FUSE 安装失败" "error"
        return 1
    fi
}

### 初始化检查函数 ###
init_check() {
    # 检查是否为 root 用户
    if [[ $EUID -ne 0 ]]; then
        echo "错误: 此脚本需要 root 权限运行"
        exit 1
    fi

    # 定义配置文件路径（确保在使用前已定义）
    CONFIG_FILE="${CONFIG_FILE:-/etc/backup_script/config}"
    LOG_DIR="${LOG_DIR:-/var/log/backup_script}"

    # 检查必要的命令
    local required_commands=("rclone" "rsync" "curl" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "错误: 未找到命令 '$cmd'"
            echo "请安装所需的包。"
            exit 1
        fi
    done

    # 检查并安装 FUSE
    if ! command -v fusermount3 >/dev/null 2>&1 && ! command -v fusermount >/dev/null 2>&1; then
        install_fuse || {
            print_status "无法安装 FUSE，请手动安装 fuse 或 fuse3 包" "error"
            exit 1
        }
    fi

    # 检查配置文件目录
    if [ ! -d "$(dirname "$CONFIG_FILE")" ]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
    fi

    # 检查配置文件
    if [ ! -f "$CONFIG_FILE" ]; then
        print_status "配置文件不存在，将进入配置向导" "info"
        setup_wizard
    fi

    # 检查日志目录
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
    fi

    # 初始化界面
    init_ui
}

### 安装依赖 ###
install_dependencies() {
    local packages=()
    local install_cmd=""
    local update_cmd=""

    # 根据系统类型设置包管理器命令
    case "${OS,,}" in
    debian | ubuntu)
        install_cmd="apt-get install -y"
        update_cmd="apt-get update"
        packages=(rclone fuse rsync cron curl wget sudo)
        ;;
    centos | rhel | fedora)
        install_cmd="yum install -y"
        update_cmd="yum check-update"
        packages=(rclone fuse rsync cronie curl wget sudo)
        ;;
    suse)
        install_cmd="zypper install -y"
        update_cmd="zypper refresh"
        packages=(rclone fuse rsync cron curl wget sudo)
        ;;
    alpine)
        install_cmd="apk add"
        update_cmd="apk update"
        packages=(rclone fuse rsync dcron curl wget sudo)
        ;;
    *)
        print_status "未知的系统类型: $OS" "error"
        print_status "请手动安装以下包: rclone, fuse, rsync, cron, curl, wget, sudo" "info"
        return 1
        ;;
    esac

    # 更新包管理器缓存
    print_status "更新包管理器缓存..." "info"
    $update_cmd >/dev/null 2>&1

    # 检查并安装缺失的包
    local missing_packages=()
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$pkg" 2>/dev/null &&
            ! rpm -q "$pkg" >/dev/null 2>&1 &&
            ! apk info -e "$pkg" >/dev/null 2>&1; then
            missing_packages+=("$pkg")
        fi
    done

    # 特殊检查 rclone（可能是通过其他方式安装的）
    if ! command -v rclone >/dev/null 2>&1; then
        print_status "未检测到 rclone，尝试安装..." "info"
        if ! curl https://rclone.org/install.sh | sudo bash; then
            print_status "rclone 安装失败" "error"
            return 1
        fi
    fi

    if [ ${#missing_packages[@]} -ne 0 ]; then
        print_status "正在安装缺失的依赖: ${missing_packages[*]}" "info"
        if ! $install_cmd "${missing_packages[@]}" >/dev/null 2>&1; then
            print_status "部分包安装失败，尝试逐个安装" "warning"
            for pkg in "${missing_packages[@]}"; do
                print_status "安装 $pkg..." "info"
                if $install_cmd "$pkg" >/dev/null 2>&1; then
                    print_status "$pkg 安装成功" "success"
                else
                    print_status "$pkg 安装失败" "error"
                fi
            done
        else
            print_status "所有依赖安装成功" "success"
        fi
    else
        print_status "所有依赖已安装" "success"
    fi

    # 验证必要的命令是否可用
    local required_commands=(rclone rsync fusermount mount)
    local missing_commands=()

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -ne 0 ]; then
        print_status "警告：以下命令未找到: ${missing_commands[*]}" "error"
        return 1
    fi

    return 0
}

### 基础函数 ###
log() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 不使用颜色代码，使用纯文本输出
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_DIR}/cron_backup.log"
}

### 环境变量设置 ###
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export SHELL="/bin/bash"
export HOME="/root" # 确保 rclone 配置可以被找到

# 设置资源限制
ulimit -n 1024    # 文件描述符限制
ulimit -u 100     # 进程数限制
ulimit -v 1048576 # 虚拟内存限制（KB）

### 初始化配置 ###
TEMP_CONFIG="/tmp/backup_temp.conf"

# 只在缺少依赖时安装
check_dependencies || install_dependencies

### 初始化配置 ###
init_config() {
    # 设置脚本路径
    SCRIPT_PATH=$(readlink -f "$0")
    SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
    
    # 设置配置文件路径
    CONFIG_FILE="${SCRIPT_DIR}/backup.conf"
    
    # 如果配置文件不存在，创建默认配置
    if [ ! -f "$CONFIG_FILE" ]; then
        {
            echo "# 自动生成的备份配置"
            echo "BACKUP_MODE=2  # 1=挂载模式 2=直传模式"
            echo "declare -A BACKUP_PATHS=()"
            echo "EXCLUDE_PATTERNS=()"
            echo "DEST_ROOT='/mnt/data'"
            echo "RCLONE_REMOTE=''"
            echo "LOG_DIR='/var/log/backups'"
            echo "MAX_LOG_DAYS=30"
            echo "RCLONE_CONFIG='$HOME/.config/rclone/rclone.conf'"
        } | sudo tee "$CONFIG_FILE" >/dev/null
        sudo chmod 644 "$CONFIG_FILE"
    fi
    
    # 确保日志目录存在
    LOG_DIR=${LOG_DIR:-/var/log/backups}
    sudo mkdir -p "$LOG_DIR"
    sudo chmod 755 "$LOG_DIR"
    
    # 加载配置文件
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        print_status "无法创建配置文件" "error"
        exit 1
    fi
}

### 修改配置函数 ###
modify_config() {
    # 确保基本配置变量已初始化
    BACKUP_MODE=${BACKUP_MODE:-2}  # 默认为直传模式
    DEST_ROOT=${DEST_ROOT:-"/mnt/data"}  # 默认挂载点
    RCLONE_REMOTE=${RCLONE_REMOTE:-""}  # 远程存储配置
    LOG_DIR=${LOG_DIR:-"/var/log/backup_script"}  # 日志目录
    
    while true; do
        print_header "修改配置"
        
        # 获取备份模式显示文本
        local mode_text="未设置"
        if [ "$BACKUP_MODE" -eq 1 ]; then
            mode_text="挂载模式"
        elif [ "$BACKUP_MODE" -eq 2 ]; then
            mode_text="直传模式"
        fi

        # 获取挂载点显示文本
        local mount_text="${DEST_ROOT:-未设置}"
        
        # 获取远程存储显示文本
        local remote_text="${RCLONE_REMOTE:-未设置}"
        
        echo -e "\n选择要修改的配置项:"
        print_menu_item "1" "修改备份模式 (当前: $mode_text)"
        print_menu_item "2" "修改本地挂载点 (当前: $mount_text)"
        print_menu_item "3" "修改远程存储配置 (当前: $remote_text)"
        print_menu_item "4" "修改日志配置"
        print_menu_item "5" "管理备份路径"
        print_menu_item "6" "管理排除规则"
        print_menu_item "q" "返回上级菜单"

        echo -e "\n${GRAY}请选择 [1-6/q]:${NC} \c"
        read -r choice

        case $choice in
            [qQ]) return 0 ;;
            1)
                echo -e "\n选择备份模式:"
                print_menu_item "1" "挂载模式 - 将远程存储挂载到本地后备份"
                print_menu_item "2" "直传模式 - 直接传输到远程存储"
                echo -e "\n${GRAY}请选择 [1-2]:${NC} \c"
                read -r mode
                if [[ "$mode" =~ ^[12]$ ]]; then
                    sudo sed -i "s/^BACKUP_MODE=.*/BACKUP_MODE=$mode/" "$CONFIG_FILE"
                    BACKUP_MODE=$mode
                    print_status "备份模式已更新" "success"
                else
                    print_status "无效选择" "error"
                fi
                sleep 1
                ;;
            2)
                echo -e "\n${CYAN}输入新的挂载点路径 (当前: $mount_text):${NC} \c"
                read -r new_path
                if [ -n "$new_path" ]; then
                    if sudo mkdir -p "$new_path" 2>/dev/null; then
                        sudo sed -i "s|^DEST_ROOT=.*|DEST_ROOT='$new_path'|" "$CONFIG_FILE"
                        DEST_ROOT="$new_path"
                        print_status "挂载点已更新" "success"
                    else
                        print_status "创建目录失败" "error"
                    fi
                fi
                sleep 1
                ;;
            3) # 远程存储配置
                print_header "Rclone远程配置"

                # 检查rclone是否安装
                if ! command -v rclone &>/dev/null; then
                    print_status "未找到rclone，正在安装..." "info"
                    install_dependencies || {
                        print_status "rclone 安装失败" "error"
                        sleep 1
                        continue
                    }
                fi

                # 检查rclone配置文件
                RCLONE_CONFIG=${RCLONE_CONFIG:-"$HOME/.config/rclone/rclone.conf"}
                if [ ! -f "$RCLONE_CONFIG" ]; then
                    print_status "未找到rclone配置文件，请先配置rclone" "warning"
                    echo -e "\n是否现在配置rclone? [Y/n] \c"
                    read -r choice
                    if [[ $choice =~ ^[Yy]$ ]] || [ -z "$choice" ]; then
                        rclone config
                    else
                        continue
                    fi
                fi

                # 获取可用的远程存储列表
                echo -e "\n当前可用的远程存储:"
                local available_remotes=($(rclone listremotes 2>/dev/null))
                
                if [ ${#available_remotes[@]} -eq 0 ]; then
                    print_status "没有找到可用的远程存储" "warning"
                    echo -e "\n是否要配置新的远程存储? [Y/n] \c"
                    read -r choice
                    if [[ $choice =~ ^[Yy]$ ]] || [ -z "$choice" ]; then
                        rclone config
                        # 重新获取远程存储列表
                        available_remotes=($(rclone listremotes 2>/dev/null))
                    else
                        continue
                    fi
                fi

                # 显示可用的远程存储
                for i in "${!available_remotes[@]}"; do
                    print_menu_item "$((i+1))" "${available_remotes[i]%:}"
                done
                print_menu_item "n" "配置新的远程存储"
                print_menu_item "b" "返回"

                echo -e "\n${GRAY}选择远程存储 [1-${#available_remotes[@]}/n/b]:${NC} \c"
                read -r remote_choice

                case $remote_choice in
                    [bB]) continue ;;
                    [nN])
                        rclone config
                        continue
                        ;;
                    *)
                        if [[ "$remote_choice" =~ ^[0-9]+$ ]] && [ "$remote_choice" -ge 1 ] && [ "$remote_choice" -le "${#available_remotes[@]}" ]; then
                            selected_remote="${available_remotes[$((remote_choice-1))]}"
                            
                            # 列出远程存储的根目录
                            echo -e "\n正在获取 ${selected_remote} 的目录列表..."
                            if ! readarray -t remote_dirs < <(rclone lsd "${selected_remote}" 2>/dev/null | awk '{print $NF}'); then
                                remote_dirs=()
                            fi

                            echo -e "\n可用的目录:"
                            for i in "${!remote_dirs[@]}"; do
                                print_menu_item "$((i+1))" "${remote_dirs[i]}"
                            done
                            print_menu_item "$((${#remote_dirs[@]}+1))" "使用根目录"
                            print_menu_item "$((${#remote_dirs[@]}+2))" "创建新目录"
                            print_menu_item "b" "返回"

                            echo -e "\n${GRAY}选择目录 [1-$((${#remote_dirs[@]}+2))/b]:${NC} \c"
                            read -r dir_choice

                            case $dir_choice in
                                [bB]) continue ;;
                                *)
                                    if [ "$dir_choice" -eq "$((${#remote_dirs[@]}+2))" ]; then
                                        echo -e "\n${CYAN}输入新目录名:${NC} \c"
                                        read -r new_dir
                                        if [ -n "$new_dir" ]; then
                                            if rclone mkdir "${selected_remote}${new_dir}"; then
                                                remote_path="$new_dir"
                                                print_status "目录创建成功" "success"
                                            else
                                                print_status "目录创建失败" "error"
                                                sleep 1
                                                continue
                                            fi
                                        fi
                                    elif [ "$dir_choice" -eq "$((${#remote_dirs[@]}+1))" ]; then
                                        remote_path=""
                                    elif [[ "$dir_choice" =~ ^[0-9]+$ ]] && [ "$dir_choice" -ge 1 ] && [ "$dir_choice" -le "${#remote_dirs[@]}" ]; then
                                        remote_path="${remote_dirs[$((dir_choice-1))]}"
                                    else
                                        print_status "无效选择" "error"
                                        sleep 1
                                        continue
                                    fi

                                    # 更新配置文件
                                    if [ -n "$remote_path" ]; then
                                        RCLONE_REMOTE="${selected_remote%:}:$remote_path"
                                    else
                                        RCLONE_REMOTE="${selected_remote%:}"
                                    fi
                                    sudo sed -i "s|^RCLONE_REMOTE=.*|RCLONE_REMOTE='$RCLONE_REMOTE'|" "$CONFIG_FILE"
                                    print_status "远程存储配置已更新: $RCLONE_REMOTE" "success"
                                    sleep 1
                                    ;;
                            esac
                        else
                            print_status "无效选择" "error"
                            sleep 1
                        fi
                        ;;
                esac
                ;;
            4)
                modify_log_config
                ;;
            5)
                manage_backup_paths
                ;;
            6)
                manage_exclude_patterns
                ;;
            *)
                print_status "无效选择" "error"
                sleep 1
                ;;
        esac
    done
}

### 交互配置向导 ###
setup_wizard() {
    while true; do
        print_header "备份配置向导"
        
        echo -e "\n选择备份方式:"
        print_menu_item "1" "挂载模式 - 将远程存储挂载到本地后备份 (适合需要频繁访问的场景)"
        print_menu_item "2" "直传模式 - 直接传输到远程存储 (更可靠，但不能直接访问文件)"
        print_menu_item "q" "返回上级菜单"
        
        echo -e "\n${GRAY}请选择备份方式 [1/2/q]:${NC} \c"
        read backup_mode
        case $backup_mode in
            [qQ]) return 1 ;;  # 返回错误状态，表示用户取消
            1|2) break ;;
            *) print_status "请输入1或2" "error"; sleep 1 ;;
        esac
    done

    # 初始化配置数组
    declare -A BACKUP_PATHS
    EXCLUDE_PATTERNS=()

    # 加载现有配置（如果存在）
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        echo "检测到现有配置，将在其基础上修改"
    fi

    # 备份路径配置
    while true; do
        echo -e "\n\033[36m当前备份路径配置：\033[0m"
        for path in "${!BACKUP_PATHS[@]}"; do
            echo "  [${BACKUP_PATHS[$path]}] ← $path"
        done

        read -p $'\n1) 添加备份路径\n2) 删除路径\n3) 完成配置\n请选择操作: ' path_op
        case $path_op in
        1)
            while true; do
                read -p "请输入要备份的源目录（绝对路径）: " src
                if [[ ! -d "$src" ]]; then
                    echo "错误：目录不存在，请重新输入"
                    continue
                fi
                src=$(realpath "$src")

                read -p "请输入远程存储中的目标目录名（不要包含/）: " dest
                if [[ "$dest" =~ [/\\] ]]; then
                    echo "错误：目标名不能包含路径分隔符"
                    continue
                fi

                BACKUP_PATHS["$src"]="$dest"
                break
            done
            ;;
        2)
            read -p "请输入要删除的源目录（精确匹配）: " del_path
            unset BACKUP_PATHS["$del_path"]
            ;;
        3) break ;;
        *) echo "无效选项" ;;
        esac
    done

    # 排除模式配置
    echo -e "\n\033[36m当前排除模式：${EXCLUDE_PATTERNS[*]}\033[0m"
    read -p "是否修改排除模式？(y/N) " modify_exclude
    if [[ $modify_exclude =~ [Yy] ]]; then
        EXCLUDE_PATTERNS=()
        echo "请输入要排除的模式（每行一个，空行结束）："
        while read -p "> " pattern && [[ -n "$pattern" ]]; do
            EXCLUDE_PATTERNS+=("$pattern")
        done
    fi

    # Rclone配置检测
    if ! command -v rclone &>/dev/null; then
        echo -e "\n\033[33m未找到rclone，即将启动安装...\033[0m"
        install_dependencies
    fi

    # 新增远程路径配置 -------------------------
    echo -e "\n\033[36m=== Rclone远程路径配置 ===\033[0m"
    echo "当前远程路径：${RCLONE_REMOTE:-（未设置）}"
    while true; do
        read -p "请输入新的远程路径 (格式：存储名:子路径 如 onedrive:vkvm): " rclone_remote
        if [[ "$rclone_remote" =~ ^[a-zA-Z0-9_-]+:[a-zA-Z0-9_/-]+$ ]]; then
            RCLONE_REMOTE="$rclone_remote"
            break
        elif [[ -z "$rclone_remote" && -n "$RCLONE_REMOTE" ]]; then
            # 允许跳过保留现有配置
            break
        else
            echo "错误：格式应为 存储配置名:路径（示例：onedrive:backups/vm）"
        fi
    done

    # 生成配置文件
    echo -e "\n\033[36m正在生成配置文件...\033[0m"
    {
        echo "# 自动生成的备份配置"
        echo "BACKUP_MODE=$backup_mode  # 1=挂载模式 2=直传模式"
        echo "declare -A BACKUP_PATHS=("
        for key in "${!BACKUP_PATHS[@]}"; do
            echo "    ['$key']='${BACKUP_PATHS[$key]}'"
        done
        echo ")"
        echo "EXCLUDE_PATTERNS=(${EXCLUDE_PATTERNS[@]@Q})"
        echo "DEST_ROOT='${DEST_ROOT:-/mnt/data}'"
        echo "RCLONE_REMOTE='${RCLONE_REMOTE}'"
        echo "LOG_DIR='${LOG_DIR:-/var/log/backups}'"
        echo "MAX_LOG_DAYS=${MAX_LOG_DAYS:-30}"
        echo "RCLONE_CONFIG='${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}'"
    } | sudo tee "$CONFIG_FILE" >/dev/null

    echo -e "\033[32m配置已保存至 $CONFIG_FILE\033[0m"
}

### 计划任务管理 ###
manage_schedule() {
    # 禁用任何可能影响输入的设置
    stty sane
    
    while : ; do
        # 清屏并显示菜单
        clear
        print_header "计划任务管理"
        
        # 获取当前所有备份任务
        echo -e "\n${CYAN}当前备份计划任务:${NC}"
        crontab_content=$(crontab -l 2>/dev/null || echo "")
        
        if [ -z "$crontab_content" ] || ! grep -q "backup_script.sh" <<< "$crontab_content"; then
            echo -e "  ${YELLOW}未设置备份计划任务${NC}"
        else
            while IFS= read -r line; do
                if [[ "$line" == *"backup_script.sh"* ]]; then
                    cron_schedule=$(echo "$line" | awk '{printf "%s %s %s %s %s", $1,$2,$3,$4,$5}')
                    echo -e "  ${CYAN}•${NC} $cron_schedule - 备份任务"
                fi
            done <<< "$crontab_content"
        fi
        
        echo -e "\n${BLUE}$(printf '%*s' "$BOX_WIDTH" '' | tr ' ' '.')${NC}"
        
        echo -e "\n选择操作:"
        print_menu_item "1" "添加每日备份任务"
        print_menu_item "2" "添加每周备份任务"
        print_menu_item "3" "添加每月备份任务"
        print_menu_item "4" "自定义备份计划"
        print_menu_item "5" "删除指定备份任务"
        print_menu_item "6" "删除所有备份任务"
        print_menu_item "q" "返回上级菜单"
        
        printf "\n${GRAY}请选择操作 [1-6/q]:${NC} "
        read input
        
        [ -z "$input" ] && continue
        
        case "$input" in
            q|Q) 
                clear
                break
                ;;
            1)  # 添加每日备份
                printf "\n${CYAN}请输入每日备份时间 (格式: HH:MM):${NC} "
                read time
                if [[ "$time" =~ ^([0-1][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
                    hour=${time%:*}
                    minute=${time#*:}
                    (crontab -l 2>/dev/null; echo "$minute $hour * * * cd $(dirname "$0") && TERM=xterm $0 main >> $LOG_DIR/cron_backup.log 2>&1") | crontab -
                    print_status "已添加每日备份任务：每天 $time" "success"
                else
                    print_status "无效的时间格式" "error"
                fi
                sleep 2
                ;;
            2)  # 添加每周备份
                echo -e "\n选择备份日期:"
                print_menu_item "1" "周一"
                print_menu_item "2" "周二"
                print_menu_item "3" "周三"
                print_menu_item "4" "周四"
                print_menu_item "5" "周五"
                print_menu_item "6" "周六"
                print_menu_item "7" "周日"
                printf "\n${GRAY}请选择 [1-7]:${NC} "
                read day
                if [[ "$day" =~ ^[1-7]$ ]]; then
                    printf "\n${CYAN}请输入备份时间 (格式: HH:MM):${NC} "
                    read time
                    if [[ "$time" =~ ^([0-1][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
                        hour=${time%:*}
                        minute=${time#*:}
                        (crontab -l 2>/dev/null; echo "$minute $hour * * $day cd $(dirname "$0") && TERM=xterm $0 main >> $LOG_DIR/cron_backup.log 2>&1") | crontab -
                        print_status "已添加每周备份任务：每周$(printf '%d' "$day") $time" "success"
                    else
                        print_status "无效的时间格式" "error"
                    fi
                else
                    print_status "无效的日期选择" "error"
                fi
                sleep 2
                ;;
            3)  # 添加每月备份
                printf "\n${CYAN}请输入每月几号备份 (1-31):${NC} "
                read day
                if [[ "$day" =~ ^([1-9]|[12][0-9]|3[01])$ ]]; then
                    printf "\n${CYAN}请输入备份时间 (格式: HH:MM):${NC} "
                    read time
                    if [[ "$time" =~ ^([0-1][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
                        hour=${time%:*}
                        minute=${time#*:}
                        (crontab -l 2>/dev/null; echo "$minute $hour $day * * cd $(dirname "$0") && TERM=xterm $0 main >> $LOG_DIR/cron_backup.log 2>&1") | crontab -
                        print_status "已添加每月备份任务：每月${day}号 $time" "success"
                    else
                        print_status "无效的时间格式" "error"
                    fi
                else
                    print_status "无效的日期" "error"
                fi
                sleep 2
                ;;
            4)  # 自定义备份计划
                printf "\n${CYAN}请输入cron表达式 (分 时 日 月 周):${NC} "
                read cron
                if [[ "$cron" =~ ^[0-9*/-]+" "[0-9*/-]+" "[0-9*/-]+" "[0-9*/-]+" "[0-9*/-]+$ ]]; then
                    (crontab -l 2>/dev/null; echo "$cron cd $(dirname "$0") && TERM=xterm $0 main >> $LOG_DIR/cron_backup.log 2>&1") | crontab -
                    print_status "已添加自定义备份任务：$cron" "success"
                else
                    print_status "无效的cron表达式" "error"
                fi
                sleep 2
                ;;
            5)  # 删除指定备份任务
                if ! crontab -l 2>/dev/null | grep -q "backup_script.sh"; then
                    print_status "没有可删除的任务" "warning"
                    sleep 2
                    continue
                fi
                
                echo -e "\n当前备份任务:"
                crontab -l | grep -n "backup_script.sh"
                printf "\n${CYAN}请输入要删除的任务行号:${NC} "
                read line_number
                
                if [[ "$line_number" =~ ^[0-9]+$ ]]; then
                    crontab -l | sed "${line_number}d" | crontab -
                    print_status "已删除指定的备份任务" "success"
                else
                    print_status "无效的行号" "error"
                fi
                sleep 2
                ;;
            6)  # 删除所有备份任务
                if crontab -l 2>/dev/null | grep -q "backup_script.sh"; then
                    crontab -l | grep -v "backup_script.sh" | crontab -
                    print_status "已删除所有备份任务" "success"
                else
                    print_status "没有可删除的任务" "warning"
                fi
                sleep 2
                ;;
            *)
                print_status "无效选择" "error"
                sleep 2
                ;;
        esac
    done
}

### 查看日志 ###
view_logs() {
    while true; do
        print_header "备份日志查看"

        echo -e "\n选择操作:"
        print_menu_item "1" "查看今日备份日志"
        print_menu_item "2" "查看今日Rclone日志"
        print_menu_item "3" "查看历史备份日志"
        print_menu_item "4" "查看历史Rclone日志"
        print_menu_item "q" "返回上级菜单"

        echo -e "\n${GRAY}请选择操作 [1-4/q]:${NC} \c"
        read log_choice
        case $log_choice in
            [qQ]) return 0 ;;
            1)
                print_header "今日备份日志"
                if [[ -f "$LOG_FILE" ]]; then
                    less "$LOG_FILE"
                else
                    print_status "今日暂无备份日志" "warning"
                    sleep 1
                fi
                ;;
            2)
                print_header "今日Rclone日志"
                if [[ -f "$RCLONE_LOG" ]]; then
                    less "$RCLONE_LOG"
                else
                    print_status "今日暂无Rclone日志" "warning"
                    sleep 1
                fi
                ;;
            3)
                while true; do
                    print_header "历史备份日志"
                    echo -e "\n可用的备份日志:"
                    readarray -t log_files < <(ls -1t "$LOG_DIR"/backup_*.log 2>/dev/null)
                    
                    if [[ ${#log_files[@]} -eq 0 ]]; then
                        print_status "未找到历史备份日志" "warning"
                        sleep 1
                        break
                    fi

                    for i in "${!log_files[@]}"; do
                        print_menu_item "$((i+1))" "$(basename "${log_files[i]}")"
                    done
                    print_menu_item "b" "返回上一步"
                    print_menu_item "q" "返回主菜单"

                    echo -e "\n${GRAY}选择要查看的日志 [1-${#log_files[@]}/b/q]:${NC} \c"
                    read file_choice
                    case $file_choice in
                        [qQ]) return 0 ;;
                        [bB]) break ;;
                        *)
                            if [[ "$file_choice" =~ ^[0-9]+$ ]] && \
                               (( file_choice >= 1 && file_choice <= ${#log_files[@]} )); then
                                less "${log_files[file_choice-1]}"
                            else
                                print_status "无效选择" "error"
                                sleep 1
                            fi
                            ;;
                    esac
                done
                ;;
            4)
                # 类似于选项3的实现，但是针对Rclone日志
                ;;
            *)
                print_status "无效选择" "error"
                sleep 1
                ;;
        esac
    done
}

### 日志清理函数 ###
cleanup_all_logs() {
    while true; do
        print_header "日志清理"
        
        echo -e "\n当前日志状态:"
        echo "备份日志数量: $(ls -1 "$LOG_DIR"/backup_*.log 2>/dev/null | wc -l)"
        echo "Rclone日志数量: $(ls -1 "$LOG_DIR"/rclone_*.log 2>/dev/null | wc -l)"
        echo "日志总大小: $(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)"

        echo -e "\n选择操作:"
        print_menu_item "1" "清理所有日志"
        print_menu_item "2" "仅清理备份日志"
        print_menu_item "3" "仅清理Rclone日志"
        print_menu_item "4" "清理指定天数前的日志"
        print_menu_item "q" "返回上级菜单"

        echo -e "\n${GRAY}请选择操作 [1-4/q]:${NC} \c"
        read cleanup_choice
        case $cleanup_choice in
            1)
                print_status "正在清理所有日志..." "info"
                rm -f "$LOG_DIR"/backup_*.log "$LOG_DIR"/rclone_*.log 2>/dev/null
                print_status "日志清理完成" "success"
                sleep 1
                ;;
            2)
                print_status "正在清理备份日志..." "info"
                rm -f "$LOG_DIR"/backup_*.log 2>/dev/null
                print_status "备份日志清理完成" "success"
                sleep 1
                ;;
            3)
                print_status "正在清理Rclone日志..." "info"
                rm -f "$LOG_DIR"/rclone_*.log 2>/dev/null
                print_status "Rclone日志清理完成" "success"
                sleep 1
                ;;
            4)
                echo -e "\n${GRAY}请输入要保留的天数:${NC} \c"
                read days
                if [[ "$days" =~ ^[0-9]+$ ]]; then
                    print_status "正在清理${days}天前的日志..." "info"
                    find "$LOG_DIR" -name "*.log" -type f -mtime +$days -delete
                    print_status "日志清理完成" "success"
                else
                    print_status "无效的天数" "error"
                fi
                sleep 1
                ;;
            [qQ])
                return 0
                ;;
            *)
                print_status "无效选择，请重试" "error"
                sleep 1
                ;;
        esac
    done
}

### 添加挂载状态检查函数
check_mount_status() {
    local mount_point="$1"
    
    # 检查挂载点是否存在
    if [ ! -d "$mount_point" ]; then
        return 1
    fi
    
    # 检查是否是有效的挂载点
    if ! mountpoint -q "$mount_point" 2>/dev/null; then
        return 1
    fi
    
    # 尝试读取目录内容
    if ! timeout 5s ls "$mount_point" >/dev/null 2>&1; then
        return 1
    fi
    
    # 检查 rclone 进程
    if ! pgrep -f "rclone.*${mount_point}" >/dev/null; then
        return 1
    fi
    
    return 0
}

### 挂载向导 ###
mount_wizard() {
    while true; do
        print_header "挂载向导"

        # 显示当前挂载状态
        echo -e "\n当前系统挂载状态:"
        if mount | grep "rclone" >/dev/null; then
            echo "已挂载的 rclone 存储:"
            mount | grep "rclone" | while read -r line; do
                if check_mount_status "$(echo "$line" | awk '{print $3}')"; then
                    print_status "$line" "success"
                else
                    print_status "$line (已断开)" "error"
                fi
            done
            
            # 添加卸载选项
            echo -e "\n是否需要卸载已有挂载点?"
            print_menu_item "1" "继续挂载新目录"
            print_menu_item "2" "卸载所有挂载点"
            print_menu_item "3" "卸载指定挂载点"
            print_menu_item "q" "返回上级菜单"
            
            echo -e "\n${GRAY}请选择 [1-3/q]:${NC} \c"
            read unmount_choice
            
            case "$unmount_choice" in
                2)
                    print_status "正在卸载所有挂载点..." "info"
                    mount | grep "rclone" | awk '{print $3}' | while read -r mount_point; do
                        if fusermount -u "$mount_point" 2>/dev/null; then
                            print_status "已卸载: $mount_point" "success"
                        else
                            print_status "卸载失败: $mount_point" "error"
                        fi
                    done
                    sleep 2
                    continue
                    ;;
                3)
                    echo -e "\n当前挂载点:"
                    mount_points=($(mount | grep "rclone" | awk '{print $3}'))
                    for i in "${!mount_points[@]}"; do
                        print_menu_item "$((i + 1))" "${mount_points[i]}"
                    done
                    print_menu_item "b" "返回"
                    
                    echo -e "\n${GRAY}选择要卸载的挂载点 [1-${#mount_points[@]}/b]:${NC} \c"
                    read point_choice
                    
                    if [[ "$point_choice" =~ ^[0-9]+$ ]] && ((point_choice >= 1 && point_choice <= ${#mount_points[@]})); then
                        selected_point="${mount_points[point_choice - 1]}"
                        if fusermount -u "$selected_point" 2>/dev/null; then
                            print_status "已卸载: $selected_point" "success"
                        else
                            print_status "卸载失败: $selected_point" "error"
                        fi
                        sleep 2
                    fi
                    continue
                    ;;
                [qQ]) return 0 ;;
            esac
        else
            print_status "未发现 rclone 挂载点" "info"
        fi

        # 直接列出可用的远程存储，不等待回车
        echo -e "\n可用的远程存储:"
        available_remotes=($(rclone listremotes))
        if [[ ${#available_remotes[@]} -eq 0 ]]; then
            print_status "没有找到可用的远程存储，请先运行 rclone config 配置" "error"
            echo -e "\n${GRAY}按回车键返回${NC}"
            read
            return 1
        fi

        # 显示远程存储列表
        for i in "${!available_remotes[@]}"; do
            print_menu_item "$((i + 1))" "${available_remotes[i]%:}"
        done
        print_menu_item "q" "返回上级菜单"

        # 继续挂载流程
        echo -e "\n${GRAY}选择要挂载的远程存储 [1-${#available_remotes[@]}/q]:${NC} \c"
        read remote_choice

        case "$remote_choice" in
            [qQ]) return 0 ;;
            *)
                if [[ "$remote_choice" =~ ^[0-9]+$ ]] && ((remote_choice >= 1 && remote_choice <= ${#available_remotes[@]})); then
                    selected_remote="${available_remotes[remote_choice - 1]}"

                    # 列出远程存储的根目录
                    echo -e "\n正在获取 ${selected_remote} 的目录列表..."
                    readarray -t remote_dirs < <(rclone lsd "${selected_remote}" 2>/dev/null | awk '{print $NF}')

                    echo -e "\n可用的目录:"
                    for i in "${!remote_dirs[@]}"; do
                        print_menu_item "$((i + 1))" "${remote_dirs[i]}"
                    done
                    print_menu_item "$((${#remote_dirs[@]} + 1))" "使用根目录"
                    print_menu_item "$((${#remote_dirs[@]} + 2))" "输入自定义路径"
                    print_menu_item "b" "返回上一步"
                    print_menu_item "q" "返回主菜单"

                    while true; do
                        echo -e "\n${GRAY}选择要挂载的目录 [1-$((${#remote_dirs[@]} + 2))/b/q]:${NC} \c"
                        read dir_choice
                        case "$dir_choice" in
                            [qQ]) return 0 ;;
                            [bB]) break ;;
                            *)
                                if ((dir_choice >= 1 && dir_choice <= ${#remote_dirs[@]})); then
                                    remote_path="${remote_dirs[dir_choice - 1]}"
                                elif ((dir_choice == ${#remote_dirs[@]} + 1)); then
                                    remote_path=""
                                elif ((dir_choice == ${#remote_dirs[@]} + 2)); then
                                    read -p "输入自定义路径: " remote_path
                                else
                                    print_status "无效选择" "error"
                                    continue
                                fi

                                # 设置挂载点
                                echo -e "\n选择挂载点:"
                                print_menu_item "1" "使用默认挂载点 (/mnt/${selected_remote%:}_${remote_path})"
                                print_menu_item "2" "输入自定义挂载点"
                                print_menu_item "b" "返回上一步"
                                
                                echo -e "\n${GRAY}请选择 [1-2/b]:${NC} \c"
                                read mount_choice
                                
                                case "$mount_choice" in
                                    1)
                                        mount_point="/mnt/${selected_remote%:}_${remote_path}"
                                        ;;
                                    2)
                                        read -p "输入自定义挂载点: " mount_point
                                        ;;
                                    [bB])
                                        continue
                                        ;;
                                    *)
                                        print_status "无效选择" "error"
                                        continue
                                        ;;
                                esac

                                # 在执行挂载前检查挂载点
                                if mountpoint -q "$mount_point" 2>/dev/null; then
                                    print_status "挂载点已被占用: $mount_point" "error"
                                    echo -e "\n${YELLOW}请先卸载该挂载点或选择其他挂载点${NC}"
                                    sleep 2
                                    continue
                                fi

                                # 执行挂载
                                print_status "正在挂载..." "info"
                                if [ -n "$remote_path" ]; then
                                    mount_cmd="${selected_remote}${remote_path}"
                                else
                                    mount_cmd="${selected_remote}"
                                fi

                                if rclone mount "$mount_cmd" "$mount_point" \
                                    --daemon \
                                    --allow-other \
                                    --vfs-cache-mode full \
                                    --vfs-cache-max-age 24h \
                                    --vfs-write-back 5s \
                                    --vfs-read-ahead 128M \
                                    --buffer-size 256M \
                                    --transfers 4 \
                                    --checkers 8 \
                                    --dir-cache-time 24h \
                                    --poll-interval 1m \
                                    --attr-timeout 1s \
                                    --vfs-read-chunk-size 32M \
                                    --vfs-read-chunk-size-limit 256M \
                                    --log-file="$LOG_DIR/rclone_mount.log" \
                                    --log-level INFO \
                                    --volname "$(basename "$mount_point")" \
                                    --no-modtime \
                                    --umask 000; then
                                    
                                    # 等待挂载点就绪
                                    sleep 2
                                    if mountpoint -q "$mount_point" 2>/dev/null; then
                                        print_status "挂载成功: $mount_cmd -> $mount_point" "success"
                                    else
                                        print_status "挂载失败: 挂载点未就绪" "error"
                                        # 显示日志
                                        if [ -f "$LOG_DIR/rclone_mount.log" ]; then
                                            echo -e "\n${CYAN}=== 挂载日志 ===${NC}"
                                            tail -n 10 "$LOG_DIR/rclone_mount.log" | grep -i "error\|failed\|fatal"
                                        fi
                                    fi
                                else
                                    print_status "挂载失败" "error"
                                    # 显示日志
                                    if [ -f "$LOG_DIR/rclone_mount.log" ]; then
                                        echo -e "\n${CYAN}=== 挂载日志 ===${NC}"
                                        tail -n 10 "$LOG_DIR/rclone_mount.log" | grep -i "error\|failed\|fatal"
                                    fi
                                    
                                    echo -e "\n${YELLOW}可能的原因:${NC}"
                                    echo "1. 挂载点被占用"
                                    echo "2. 权限不足"
                                    echo "3. rclone 进程已存在"
                                    echo "4. 认证已过期"
                                    
                                    echo -e "\n${CYAN}建议操作:${NC}"
                                    echo "1. 检查挂载点是否已被使用"
                                    echo "2. 使用 'fusermount -u $mount_point' 强制卸载"
                                    echo "3. 检查 rclone 日志: $LOG_DIR/rclone_mount.log"
                                    echo "4. 运行 'rclone config reconnect ${selected_remote%:}:' 重新认证"
                                    
                                    # 检查是否是认证问题
                                    if grep -q "unauthenticated" "$LOG_DIR/rclone_mount.log" 2>/dev/null; then
                                        echo -e "\n${YELLOW}检测到认证问题，是否要重新认证? [y/N] ${NC}\c"
                                        read -r reauth
                                        if [[ "$reauth" =~ ^[Yy]$ ]]; then
                                            if rclone config reconnect "${selected_remote%:}:" --config "$RCLONE_CONFIG"; then
                                                print_status "重新认证成功，请重试挂载" "success"
                                            else
                                                print_status "重新认证失败" "error"
                                            fi
                                        fi
                                    fi
                                fi
                                sleep 2
                                break
                                ;;
                        esac
                    done
                else
                    print_status "无效选择，请重试" "error"
                    sleep 1
                fi
                ;;
        esac
    done
}

### 查看配置 ###
view_config() {
    print_header "当前配置"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_status "配置文件不存在: $CONFIG_FILE" "error"
        echo -e "\n${GRAY}按回车键返回${NC}"
        read
        return 1
    fi
    
    # 尝试加载配置
    if ! source "$CONFIG_FILE" 2>/dev/null; then
        print_status "无法加载配置文件: $CONFIG_FILE" "error"
        echo -e "\n${GRAY}按回车键返回${NC}"
        read
        return 1
    fi
    
    # 备份模式说明
    echo -e "\n${CYAN}=== 备份模式 ===${NC}"
    if [[ ${BACKUP_MODE:-0} == 1 ]]; then
        echo -e "当前模式: ${GREEN}挂载模式${NC}"
        echo "  - 将远程存储挂载到本地后进行备份"
        echo "  - 适合需要频繁访问文件的场景"
        echo "  - 支持实时访问远程文件"
    else
        echo -e "当前模式: ${YELLOW}直传模式${NC}"
        echo "  - 直接传输文件到远程存储"
        echo "  - 更可靠，不依赖挂载点"
        echo "  - 适合纯备份场景"
    fi

    # 备份路径配置
    echo -e "\n${CYAN}=== 备份路径配置 ===${NC}"
    if [[ ${#BACKUP_PATHS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}未配置备份路径${NC}"
    else
        echo "配置的备份路径:"
        for src in "${!BACKUP_PATHS[@]}"; do
            echo -e "  ${GREEN}源路径:${NC} $src"
            echo -e "  ${BLUE}目标路径:${NC} ${BACKUP_PATHS[$src]}"
            echo "  ---"
        done
    fi

    # 排除规则
    echo -e "\n${CYAN}=== 排除规则 ===${NC}"
    if [[ ${#EXCLUDE_PATTERNS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}未配置排除规则${NC}"
    else
        echo "当前排除的文件/目录:"
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            echo -e "  ${BULLET} $pattern"
        done
    fi

    # 存储配置
    echo -e "\n${CYAN}=== 存储配置 ===${NC}"
    echo -e "${GREEN}远程存储:${NC} $RCLONE_REMOTE"
    echo -e "${GREEN}本地挂载点:${NC} $DEST_ROOT"
    if mountpoint -q "$DEST_ROOT" 2>/dev/null; then
        echo -e "${GREEN}挂载状态:${NC} 已挂载"
        df -h "$DEST_ROOT" | tail -n 1 | awk '{print "  可用空间: " $4 " / 总空间: " $2}'
    else
        echo -e "${YELLOW}挂载状态:${NC} 未挂载"
    fi

    # 日志配置
    echo -e "\n${CYAN}=== 日志配置 ===${NC}"
    echo -e "${GREEN}日志目录:${NC} $LOG_DIR"
    echo -e "${GREEN}日志保留天数:${NC} $MAX_LOG_DAYS 天"
    if [[ -d "$LOG_DIR" ]]; then
        echo "日志统计:"
        echo "  - 备份日志数量: $(ls -1 "$LOG_DIR"/backup_*.log 2>/dev/null | wc -l)"
        echo "  - Rclone日志数量: $(ls -1 "$LOG_DIR"/rclone_*.log 2>/dev/null | wc -l)"
        echo "  - 日志总大小: $(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)"
    fi

    # Rclone配置
    echo -e "\n${CYAN}=== Rclone配置 ===${NC}"
    echo -e "${GREEN}配置文件:${NC} $RCLONE_CONFIG"
    if [[ -f "$RCLONE_CONFIG" ]]; then
        echo "可用的远程存储:"
        rclone listremotes | sed 's/^/  /'
    else
        echo -e "${YELLOW}Rclone配置文件不存在${NC}"
    fi

    # 计划任务
    echo -e "\n${CYAN}=== 计划任务 ===${NC}"
    if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
        echo "当前配置的备份计划:"
        crontab -l | grep "$SCRIPT_PATH" | sed 's/^/  /'
    else
        echo -e "${YELLOW}未配置自动备份计划${NC}"
    fi

    echo -e "\n${GRAY}按回车键返回${NC}"
    read
}

### 界面配置 ###
init_ui() {
    # 设置默认值
    MIN_COLS=60
    DEFAULT_WIDTH=80
    
    # 获取终端大小并设置默认值
    TERM_COLS=$(tput cols 2>/dev/null || echo "$DEFAULT_WIDTH")
    TERM_ROWS=$(tput lines 2>/dev/null || echo "24")
    
    # 规范化数值
    TERM_COLS=$(printf '%d' "${TERM_COLS:-$DEFAULT_WIDTH}" 2>/dev/null || echo "$DEFAULT_WIDTH")
    TERM_ROWS=$(printf '%d' "${TERM_ROWS:-24}" 2>/dev/null || echo "24")
    
    # 计算 BOX_WIDTH
    BOX_WIDTH=$(printf '%d' "$((TERM_COLS - 4))" 2>/dev/null || echo "$MIN_COLS")
    
    # 确保最小宽度
    if [ "$BOX_WIDTH" -lt "$MIN_COLS" ] 2>/dev/null; then
        BOX_WIDTH=$MIN_COLS
    fi
    
    # 生成分隔线
    HLINE=$(printf '%*s' "$BOX_WIDTH" | tr ' ' '.')
    SLINE=$(printf '%*s' "$BOX_WIDTH" | tr ' ' '-')
}

### 界面辅助函数 ###
clear_screen() {
    clear
}

print_centered() {
    local text="$1"
    local width="$2"
    local padding=$(( (width - ${#text}) / 2 ))
    printf "%${padding}s%s%${padding}s" "" "$text" ""
}

center_text() {
    local text="$1"
    local width="${2:-$BOX_WIDTH}"
    local text_len="${#text}"
    local padding=0
    
    # 安全的数学计算
    width=$(printf '%d' "${width:-$BOX_WIDTH}" 2>/dev/null || echo "$BOX_WIDTH")
    padding=$(( (width - text_len) / 2 ))
    [ "$padding" -lt 0 ] && padding=0
    
    printf '%*s%s%*s' "$padding" '' "$text" "$padding" ''
}

### 菜单处理函数 ###
interactive_menu() {
    # 确保配置已初始化
    init_config
    
    while true; do
        clear_screen
        
        # ASCII 艺术标题
        echo -e "${HCYAN}"
        echo " ____                _                "
        echo "|  _ \              | |               "
        echo "| |_) |  __ _   ___ | | __ _   _ __  "
        echo "|  _ <  / _\` | / __|| |/ /| | | '_ \ "
        echo "| |_) || (_| || (__ |   < | |_| |_) |"
        echo "|____/  \__,_| \___||_|\_\ \__| .__/ "
        echo "                              | |     "
        echo "                              |_|     "
        echo -e "${NC}"

        # 显示菜单选项
        echo -e "\n${HCYAN}=== 主菜单 ===${NC}\n"
        echo -e "${HPURPLE}1${NC}) ${CYAN}运行备份任务${NC}"
        echo -e "${HPURPLE}2${NC}) ${CYAN}配置向导${NC}"
        echo -e "${HPURPLE}3${NC}) ${CYAN}计划任务管理${NC}"
        echo -e "${HPURPLE}4${NC}) ${CYAN}查看当前配置${NC}"
        echo -e "${HPURPLE}5${NC}) ${CYAN}修改配置${NC}"
        echo -e "${HPURPLE}6${NC}) ${CYAN}查看日志${NC}"
        echo -e "${HPURPLE}7${NC}) ${CYAN}清理日志${NC}"
        echo -e "${HPURPLE}8${NC}) ${CYAN}挂载管理${NC}"
        echo -e "${HPURPLE}q${NC}) ${CYAN}退出${NC}"
        
        # 用户输入处理
        echo -e "\n${HCYAN}请选择操作 ${NC}${HPURPLE}[1-8/q]${NC}: \c"
        read -r choice
        
        case "$choice" in
            1) 
                print_header "运行备份任务"
                
                # 加载配置
                source "$CONFIG_FILE" || {
                    print_status "无法加载配置文件" "error"
                    echo -e "\n${GRAY}按回车键返回${NC}"
                    read
                    continue
                }
                
                # 设置日志文件
                LOG_FILE="$LOG_DIR/backup_$(date +%Y%m%d).log"
                RCLONE_LOG="$LOG_DIR/rclone_$(date +%Y%m%d).log"
                
                # 确保日志目录存在
                mkdir -p "$LOG_DIR" 2>/dev/null || {
                    print_status "无法创建日志目录: $LOG_DIR" "error"
                    echo -e "\n${GRAY}按回车键返回${NC}"
                    read
                    continue
                }
                
                # 检查是否有备份路径配置
                if [ ${#BACKUP_PATHS[@]} -eq 0 ]; then
                    print_status "未配置任何备份路径" "error"
                    echo -e "\n${YELLOW}提示: 请先使用配置向导(选项 2)设置备份路径${NC}"
                    echo -e "\n${GRAY}按回车键返回${NC}"
                    read
                    continue
                fi
                
                # 执行备份
                local has_error=0
                for src in "${!BACKUP_PATHS[@]}"; do
                    if [ "$BACKUP_MODE" -eq 1 ]; then
                        dest="$DEST_ROOT/${BACKUP_PATHS[$src]}"
                    else
                        # 确保路径格式正确，移除可能存在的冒号
                        clean_path="${BACKUP_PATHS[$src]//:/\/}"
                        remote_path="${RCLONE_REMOTE%:}/${clean_path}"
                        
                        print_status "正在备份到: $remote_path" "info"
                        
                        if rclone sync "$src" "$remote_path" \
                            --config "$RCLONE_CONFIG" \
                            ${EXCLUDE_PATTERNS[@]/#/--exclude } \
                            --log-file "$RCLONE_LOG" \
                            --progress \
                            --retries 3 \
                            --low-level-retries 10 \
                            --timeout 30s \
                            --transfers 4 \
                            --checkers 8 \
                            --stats 1s \
                            --use-json-log \
                            >> "$LOG_FILE" 2>&1; then
                            print_status "备份完成: $src" "success"
                        else
                            if grep -q "unauthenticated" "$RCLONE_LOG"; then
                                print_status "认证失败，请运行 'rclone config reconnect ${RCLONE_REMOTE%:}:' 重新认证" "error"
                            else
                                print_status "备份失败: $src" "error"
                            fi
                            has_error=1
                        fi
                    fi
                done
                
                # 修改日志显示部分
                if [ $has_error -eq 1 ]; then
                    print_status "部分备份任务失败，请查看日志了解详情" "error"
                    
                    echo -e "\n${CYAN}=== 备份统计 ===${NC}"
                    if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
                        grep "Transferred:" "$LOG_FILE" | tail -n 3
                    fi
                    
                    echo -e "\n${CYAN}=== 错误信息 ===${NC}"
                    if [ -f "$RCLONE_LOG" ] && [ -s "$RCLONE_LOG" ]; then
                        grep -i "error\|failed\|fatal" "$RCLONE_LOG" | grep -v "vfs cache" | tail -n 5
                    fi
                else
                    print_status "所有备份任务已完成" "success"
                    echo -e "\n${CYAN}=== 备份统计 ===${NC}"
                    if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
                        grep "Transferred:" "$LOG_FILE" | tail -n 3
                    fi
                    
                    echo -e "\n${CYAN}=== 传输详情 ===${NC}"
                    if [ -f "$RCLONE_LOG" ] && [ -s "$RCLONE_LOG" ]; then
                        grep "Copied (new)" "$RCLONE_LOG" | tail -n 5
                    fi
                fi
                
                echo -e "\n${GRAY}按回车键返回${NC}"
                read
                ;;
            2) setup_wizard ;;
            3) manage_schedule ;;
            4) view_config ;;
            5) modify_config ;;
            6) view_logs ;;
            7) cleanup_all_logs ;;
            8) mount_wizard ;;
            [qQ]) 
                clear_screen
                echo -e "${HGREEN}感谢使用，再见！${NC}"
                exit 0 
                ;;
            *) 
                print_status "无效选择，请重试" "error"
                sleep 1 
                ;;
        esac
    done
}

### 主函数 ###
backup_main() {
    # 设置默认环境变量
    export TERM=${TERM:-xterm}
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    export SHELL=/bin/bash

    # 初始化配置
    init_config

    # 直接执行备份
    local start_time=$(date +%s)
    local backup_date=$(date +%Y%m%d_%H%M%S)

    # 记录开始信息
    print_status "开始备份任务" "info"
    log "开始备份任务" "INFO"

    # 检查配置文件
    if [ ! -f "$CONFIG_FILE" ]; then
        print_status "配置文件不存在" "error"
        log "配置文件不存在" "ERROR"
        exit 1
    fi

    # 读取配置
    source "$CONFIG_FILE"

    # 检查备份路径配置
    if [ ${#BACKUP_PATHS[@]} -eq 0 ]; then
        print_status "未配置备份路径" "error"
        log "未配置备份路径" "ERROR"
        exit 1
    fi

    # 检查并创建备份目录
    if [ "$BACKUP_MODE" -eq 1 ]; then
        # 挂载模式
        if ! mountpoint -q "$DEST_ROOT"; then
            print_status "远程存储未挂载: $DEST_ROOT" "error"
            log "远程存储未挂载: $DEST_ROOT" "ERROR"
            exit 1
        fi
        local backup_dir="$DEST_ROOT"
    else
        # 直传模式
        if ! rclone lsd "$RCLONE_REMOTE" >/dev/null 2>&1; then
            print_status "无法访问远程存储: $RCLONE_REMOTE" "error"
            log "无法访问远程存储: $RCLONE_REMOTE" "ERROR"
            exit 1
        fi
    fi

    # 遍历所有配置的备份路径
    local overall_status=0
    for src in "${!BACKUP_PATHS[@]}"; do
        local dest="${BACKUP_PATHS[$src]}"
        print_status "正在备份: $src -> $dest" "info"
        log "开始备份: $src -> $dest" "INFO"

        if [ "$BACKUP_MODE" -eq 1 ]; then
            # 挂载模式：使用rsync
            mkdir -p "${backup_dir}/${dest}"
            if ! rsync -av --delete \
                  --exclude-from=<(printf '%s\n' "${EXCLUDE_PATTERNS[@]}") \
                  "${src}/" "${backup_dir}/${dest}/" \
                  >> "${LOG_DIR}/backup.log" 2>&1; then
                print_status "备份失败: $src" "error"
                log "备份失败: $src" "ERROR"
                overall_status=1
                continue
            fi
        else
            # 直传模式：使用rclone
            if ! rclone sync "$src" "${RCLONE_REMOTE}/${dest}" \
                  --config "$RCLONE_CONFIG" \
                  ${EXCLUDE_PATTERNS[@]/#/--exclude } \
                  --log-file "$LOG_DIR/rclone.log" \
                  --progress \
                  --stats 1s; then
                print_status "备份失败: $src" "error"
                log "备份失败: $src" "ERROR"
                overall_status=1
                continue
            fi
        fi

        print_status "备份成功: $src" "success"
        log "备份成功: $src" "SUCCESS"
    done

    # 计算耗时
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    print_status "备份任务完成，耗时: ${duration}秒" "info"
    log "备份任务完成，耗时: ${duration}秒" "INFO"

    exit $overall_status
}

# 根据参数决定执行模式
if [ "$1" = "main" ]; then
    backup_main
else
    interactive_menu
fi

### 日志配置管理 ###
modify_log_config() {
    while true; do
        print_header "日志配置"
        
        echo -e "\n当前配置:"
        echo "日志目录: $LOG_DIR"
        echo "日志保留天数: $MAX_LOG_DAYS"

        echo -e "\n选择要修改的项目:"
        print_menu_item "1" "修改日志目录"
        print_menu_item "2" "修改日志保留天数"
        print_menu_item "q" "返回"

        echo -e "\n${GRAY}请选择 [1-2/q]:${NC} \c"
        read -r choice

        case $choice in
            [qQ]) return 0 ;;
            1)
                echo -e "\n${CYAN}输入新的日志目录路径 (当前: $LOG_DIR):${NC} \c"
                read -r new_log_dir
                if [ -n "$new_log_dir" ]; then
                    # 创建新目录
                    if sudo mkdir -p "$new_log_dir"; then
                        sudo chmod 755 "$new_log_dir"
                        # 更新配置
                        sudo sed -i "s|^LOG_DIR=.*|LOG_DIR='$new_log_dir'|" "$CONFIG_FILE"
                        LOG_DIR="$new_log_dir"
                        print_status "日志目录已更新" "success"
                    else
                        print_status "创建目录失败" "error"
                    fi
                fi
                sleep 1
                ;;
            2)
                echo -e "\n${CYAN}输入日志保留天数 (当前: $MAX_LOG_DAYS):${NC} \c"
                read -r new_days
                if [[ "$new_days" =~ ^[0-9]+$ ]]; then
                    sudo sed -i "s/^MAX_LOG_DAYS=.*/MAX_LOG_DAYS=$new_days/" "$CONFIG_FILE"
                    MAX_LOG_DAYS=$new_days
                    print_status "日志保留天数已更新" "success"
                else
                    print_status "无效的天数" "error"
                fi
                sleep 1
                ;;
            *)
                print_status "无效选择" "error"
                sleep 1
                ;;
        esac
    done
}

### 备份路径管理 ###
manage_backup_paths() {
    # 确保 BACKUP_PATHS 已初始化
    declare -A BACKUP_PATHS=${BACKUP_PATHS[@]+"${BACKUP_PATHS[@]}"}
    
    while true; do
        print_header "备份路径管理"
        
        echo -e "\n当前备份路径配置:"
        if [ ${#BACKUP_PATHS[@]:-0} -eq 0 ]; then
            print_status "未配置备份路径" "info"
        else
            for src in "${!BACKUP_PATHS[@]}"; do
                echo -e "  ${CYAN}[${BACKUP_PATHS[$src]}]${NC} ← $src"
            done
        fi

        echo -e "\n选择操作:"
        print_menu_item "1" "添加备份路径"
        print_menu_item "2" "删除备份路径"
        print_menu_item "q" "返回"

        echo -e "\n${GRAY}请选择 [1-2/q]:${NC} \c"
        read -r choice

        case $choice in
            [qQ]) 
                # 保存配置
                save_backup_paths
                return 0 
                ;;
            1)
                add_backup_path
                ;;
            2)
                remove_backup_path
                ;;
            *)
                print_status "无效选择" "error"
                sleep 1
                ;;
        esac
    done
}

### 添加备份路径 ###
add_backup_path() {
    while true; do
        echo -e "\n${CYAN}请输入要备份的源目录（绝对路径）:${NC} \c"
        read -r src
        
        if [ -z "$src" ]; then
            return
        fi

        if [ ! -d "$src" ]; then
            print_status "目录不存在" "error"
            continue
        fi

        src=$(realpath "$src")
        echo -e "\n${CYAN}请输入远程存储中的目标目录名（不要包含/）:${NC} \c"
        read -r dest

        if [[ "$dest" =~ [/\\] ]]; then
            print_status "目标名不能包含路径分隔符" "error"
            continue
        fi

        BACKUP_PATHS["$src"]="$dest"
        print_status "备份路径已添加" "success"
        break
    done
}

### 删除备份路径 ###
remove_backup_path() {
    # 确保 BACKUP_PATHS 已初始化
    declare -A BACKUP_PATHS=${BACKUP_PATHS[@]+"${BACKUP_PATHS[@]}"}
    
    if [ ${#BACKUP_PATHS[@]:-0} -eq 0 ]; then
        print_status "没有可删除的备份路径" "warning"
        sleep 1
        return
    fi

    echo -e "\n当前备份路径:"
    local i=1
    declare -A path_index
    for src in "${!BACKUP_PATHS[@]}"; do
        echo "  $i) $src → ${BACKUP_PATHS[$src]}"
        path_index[$i]="$src"
        ((i++))
    done

    echo -e "\n${CYAN}请输入要删除的路径编号 [1-$((i-1))]:${NC} \c"
    read -r num

    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -lt "$i" ]; then
        local path_to_remove="${path_index[$num]}"
        unset BACKUP_PATHS["$path_to_remove"]
        print_status "备份路径已删除" "success"
    else
        print_status "无效的选择" "error"
    fi
    sleep 1
}

### 保存备份路径配置 ###
save_backup_paths() {
    # 创建临时文件
    local temp_file=$(mktemp)
    
    # 读取当前配置文件
    while IFS= read -r line; do
        # 跳过旧的 BACKUP_PATHS 配置
        if [[ "$line" =~ ^declare\ -A\ BACKUP_PATHS= ]] || [[ "$line" =~ ^\[\'.*\'\]=\'.*\'$ ]]; then
            continue
        fi
        echo "$line" >> "$temp_file"
    done < "$CONFIG_FILE"

    # 添加新的 BACKUP_PATHS 配置
    echo "declare -A BACKUP_PATHS=(" >> "$temp_file"
    for src in "${!BACKUP_PATHS[@]}"; do
        echo "    ['$src']='${BACKUP_PATHS[$src]}'" >> "$temp_file"
    done
    echo ")" >> "$temp_file"

    # 替换原配置文件
    sudo mv "$temp_file" "$CONFIG_FILE"
    sudo chmod 644 "$CONFIG_FILE"
}

### 排除规则管理 ###
manage_exclude_patterns() {
    while true; do
        print_header "排除规则管理"
        
        echo -e "\n当前排除规则:"
        if [ ${#EXCLUDE_PATTERNS[@]} -eq 0 ]; then
            print_status "未配置排除规则" "info"
        else
            for i in "${!EXCLUDE_PATTERNS[@]}"; do
                echo "  $((i+1))) ${EXCLUDE_PATTERNS[i]}"
            done
        fi

        echo -e "\n选择操作:"
        print_menu_item "1" "添加排除规则"
        print_menu_item "2" "删除排除规则"
        print_menu_item "3" "清空所有规则"
        print_menu_item "q" "返回"

        echo -e "\n${GRAY}请选择 [1-3/q]:${NC} \c"
        read -r choice

        case $choice in
            [qQ]) 
                save_exclude_patterns
                return 0 
                ;;
            1)
                echo -e "\n${CYAN}输入新的排除规则 (如: *.tmp 或 .git/):${NC} \c"
                read -r pattern
                if [ -n "$pattern" ]; then
                    EXCLUDE_PATTERNS+=("$pattern")
                    print_status "规则已添加" "success"
                fi
                ;;
            2)
                if [ ${#EXCLUDE_PATTERNS[@]} -eq 0 ]; then
                    print_status "没有可删除的规则" "warning"
                else
                    echo -e "\n${CYAN}输入要删除的规则编号 [1-${#EXCLUDE_PATTERNS[@]}]:${NC} \c"
                    read -r num
                    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#EXCLUDE_PATTERNS[@]}" ]; then
                        unset 'EXCLUDE_PATTERNS[num-1]'
                        EXCLUDE_PATTERNS=("${EXCLUDE_PATTERNS[@]}")  # 重新索引数组
                        print_status "规则已删除" "success"
                    else
                        print_status "无效的编号" "error"
                    fi
                fi
                ;;
            3)
                EXCLUDE_PATTERNS=()
                print_status "已清空所有规则" "success"
                ;;
            *)
                print_status "无效选择" "error"
                ;;
        esac
                sleep 1
    done
}

### 保存排除规则配置 ###
save_exclude_patterns() {
    # 创建临时文件
    local temp_file=$(mktemp)
    
    # 读取当前配置文件
    while IFS= read -r line; do
        # 跳过旧的 EXCLUDE_PATTERNS 配置
        if [[ "$line" =~ ^EXCLUDE_PATTERNS=\( ]] || [[ "$line" =~ ^[[:space:]]*\'.*\' ]]; then
            continue
        fi
        echo "$line" >> "$temp_file"
    done < "$CONFIG_FILE"

    # 添加新的 EXCLUDE_PATTERNS 配置
    echo "EXCLUDE_PATTERNS=(" >> "$temp_file"
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        echo "    '$pattern'" >> "$temp_file"
    done
    echo ")" >> "$temp_file"

    # 替换原配置文件
    sudo mv "$temp_file" "$CONFIG_FILE"
    sudo chmod 644 "$CONFIG_FILE"
}

### 执行备份函数 ###
perform_backup() {
    # 确保配置已初始化
    init_config
    
    local start_time=$(date +%s)
    local backup_date=$(date +%Y%m%d_%H%M%S)
    local status=0

    # 记录开始信息
    print_status "开始备份任务 - $backup_date" "info"
    log "开始备份任务 - $backup_date" "INFO"

    # 检查配置文件
    if [ ! -f "$CONFIG_FILE" ]; then
        print_status "配置文件不存在" "error"
        log "配置文件不存在" "ERROR"
        return 1
    fi

    # 读取配置
    source "$CONFIG_FILE"

    # 检查备份路径配置
    if [ ${#BACKUP_PATHS[@]} -eq 0 ]; then
        print_status "未配置备份路径" "error"
        log "未配置备份路径" "ERROR"
        return 1
    fi

    # 检查目标目录
    if [ ! -d "$DEST_ROOT" ]; then
        print_status "目标目录不存在" "error"
        log "目标目录不存在: $DEST_ROOT" "ERROR"
        return 1
    fi

    # 创建备份时间戳目录
    local backup_dir="${DEST_ROOT}/backup_${backup_date}"
    mkdir -p "$backup_dir"

    # 遍历所有配置的备份路径
    local overall_status=0
    for src in "${!BACKUP_PATHS[@]}"; do
        local dest="${BACKUP_PATHS[$src]}"
        print_status "正在备份: $src -> $dest" "info"
        log "开始备份: $src -> $dest" "INFO"

        # 创建目标目录
        mkdir -p "${backup_dir}/${dest}"

        # 使用rsync进行备份
        rsync -av --delete \
              --exclude-from=<(printf '%s\n' "${EXCLUDE_PATTERNS[@]}") \
              "${src}/" "${backup_dir}/${dest}/" \
              >> "${LOG_DIR}/backup_${backup_date}.log" 2>&1

        if [ $? -eq 0 ]; then
            print_status "备份成功: $src" "success"
            log "备份成功: $src" "SUCCESS"
        else
            print_status "备份失败: $src" "error"
            log "备份失败: $src" "ERROR"
            overall_status=1
        fi
    done

    # 清理旧备份（如果配置了保留天数）
    if [ -n "$RETENTION_DAYS" ] && [ "$RETENTION_DAYS" -gt 0 ]; then
        print_status "清理${RETENTION_DAYS}天前的备份..." "info"
        log "开始清理旧备份" "INFO"
        find "$DEST_ROOT" -maxdepth 1 -type d -name "backup_*" -mtime +${RETENTION_DAYS} -exec rm -rf {} \;
    fi

    # 计算耗时
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    print_status "备份任务完成，耗时: ${duration}秒" "info"
    log "备份任务完成，耗时: ${duration}秒" "INFO"

    return $overall_status
}
