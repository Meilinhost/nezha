#!/bin/bash

#========================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+ / Alpine 3+ /
#   Arch 仅测试了一次，如有问题带截图反馈 dysf888@pm.me
#   Description: 哪吒监控安装脚本
#   Github: https://github.com/naiba/nezha
#========================================================

NZ_BASE_PATH="/opt/nezha"
NZ_DASHBOARD_PATH="${NZ_BASE_PATH}/dashboard"
NZ_DASHBOARD_SERVICE="/etc/systemd/system/nezha.service"
NZ_AGENT_PATH="${NZ_BASE_PATH}/agent"
NZ_AGENT_SERVICE="/etc/systemd/system/nezha-agent.service"
NZ_VERSION="v0.15.2"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
export PATH=$PATH:/usr/local/bin

os_arch=""
[ -e /etc/os-release ] && cat /etc/os-release | grep -i "PRETTY_NAME" | grep -qi "alpine" && os_alpine='1'

pre_check() {
    [ "$os_alpine" != 1 ] && ! command -v systemctl >/dev/null 2>&1 && echo "不支持此系统：未找到 systemctl 命令" && exit 1
    
    [[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1
    
    if [[ $(uname -m | grep 'x86_64') != "" ]]; then
        os_arch="amd64"
    elif [[ $(uname -m | grep 'i386\|i686') != "" ]]; then
        os_arch="386"
    elif [[ $(uname -m | grep 'aarch64\|armv8b\|armv8l') != "" ]]; then
        os_arch="arm64"
    elif [[ $(uname -m | grep 'arm') != "" ]]; then
        os_arch="arm"
    elif [[ $(uname -m | grep 's390x') != "" ]]; then
        os_arch="s390x"
    elif [[ $(uname -m | grep 'riscv64') != "" ]]; then
        os_arch="riscv64"
    fi
    
    if [[ -z "${CN}" ]]; then
        if [[ $(curl -m 10 -s https://ipapi.co/json | grep 'China') != "" ]]; then
            echo "根据ipapi.co提供的信息，当前IP可能在中国"
            read -e -r -p "是否选用中国镜像完成安装? [Y/n] " input
            case $input in
                [yY][eE][sS] | [yY])
                    echo "使用中国镜像"
                    CN=true
                ;;
                [nN][oO] | [nN])
                    echo "不使用中国镜像"
                ;;
                *)
                    echo "使用中国镜像"
                    CN=true
                ;;
            esac
        fi
    fi
    
    if [[ -z "${CN}" ]]; then
        GITHUB_RAW_URL="raw.githubusercontent.com/midoks/nezha/main"
        GITHUB_URL="github.com"
        Docker_IMG="ghcr.io\/naiba\/nezha-dashboard"
    else
        GITHUB_RAW_URL="cdn.jsdelivr.net/gh/midoks/nezha@main"
        GITHUB_URL="dn-dao-github-mirror.daocloud.io"
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -e -p "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -e -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

update_script() {
    echo -e "> 更新脚本"
    
    curl -sL https://${GITHUB_RAW_URL}/script/install.sh -o /tmp/nezha.sh
    new_version=$(cat /tmp/nezha.sh | grep "NZ_VERSION" | head -n 1 | awk -F "=" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$new_version" ]; then
        echo -e "脚本获取失败，请检查本机能否链接 https://${GITHUB_RAW_URL}/script/install.sh"
        return 1
    fi
    echo -e "当前最新版本为: ${new_version}"
    mv -f /tmp/nezha.sh ./nezha.sh && chmod a+x ./nezha.sh
    
    echo -e "3s后执行新脚本"
    sleep 3s
    clear
    exec ./nezha.sh
    exit 0
}

before_show_menu() {
    echo && echo -n -e "${yellow}* 按回车返回主菜单 *${plain}" && read temp
    show_menu
}

install_base() {
    (command -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && command -v wget >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1 && command -v getenforce >/dev/null 2>&1) ||
    (install_soft curl wget git unzip)
}

install_arch(){
    echo -e "${green}提示: ${plain} Arch安装libselinux需添加nezha-agent用户，安装完会自动删除，建议手动检查一次\n"
    read -e -r -p "是否安装libselinux? [Y/n] " input
    case $input in
        [yY][eE][sS] | [yY])
            useradd -m nezha-agent
            sed -i "$ a\nezha-agent ALL=(ALL ) NOPASSWD:ALL" /etc/sudoers
            sudo -iu nezha-agent bash -c 'gpg --keyserver keys.gnupg.net --recv-keys BE22091E3EF62275;
                                        cd /tmp; git clone https://aur.archlinux.org/libsepol.git; cd libsepol; makepkg -si --noconfirm --asdeps; cd ..;
                                        git clone https://aur.archlinux.org/libselinux.git; cd libselinux; makepkg -si --noconfirm; cd ..; 
                                        rm -rf libsepol libselinux'
            sed -i '/nezha-agent/d'  /etc/sudoers && sleep 30s && killall -u nezha-agent&&userdel nezha-agent
            echo -e "${red}提示: ${plain}已删除用户nezha-agent，请务必手动核查一遍！\n"
        ;;
        [nN][oO] | [nN])
            echo "不安装libselinux"
        ;;
        *)
            echo "不安装libselinux"
            exit 0
        ;;
    esac
}

install_soft() {
    (command -v yum >/dev/null 2>&1 && yum makecache && yum install $* selinux-policy -y) ||
    (command -v apt >/dev/null 2>&1 && apt update && apt install $* selinux-utils -y) ||
    (command -v pacman >/dev/null 2>&1 && pacman -Syu $* base-devel --noconfirm && install_arch)  ||
    (command -v apt-get >/dev/null 2>&1 && apt-get update && apt-get install $* selinux-utils -y) ||
    (command -v apk >/dev/null 2>&1 && apk update && apk add $* -f)
}

# === 新增：确保面板 systemd 服务文件存在 ===
ensure_dashboard_service() {
    if [[ ! -f "$NZ_DASHBOARD_SERVICE" ]]; then
        echo -e "${yellow}未检测到面板服务文件，正在自动创建...${plain}"
        cat > $NZ_DASHBOARD_SERVICE <<EOF
[Unit]
Description=Nezha Dashboard
After=network.target

[Service]
Type=simple
ExecStart=${NZ_DASHBOARD_PATH}/nezha-dashboard
WorkingDirectory=${NZ_DASHBOARD_PATH}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable nezha
    fi
}

install_dashboard() {
    install_base

    local version=$(curl -m 10 -sL "https://api.github.com/repos/midoks/nezha/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$version" ]; then
        version=$(curl -m 10 -sL "https://fastly.jsdelivr.net/gh/midoks/nezha/" | grep "option\.value" | awk -F "'" '{print $2}' | sed 's/midoks\/nezha@/v/g')
    fi
    if [ ! -n "$version" ]; then
        version=$(curl -m 10 -sL "https://gcore.jsdelivr.net/gh/midoks/nezha/" | grep "option\.value" | awk -F "'" '{print $2}' | sed 's/midoks\/nezha@/v/g')
    fi

    [[ -z "$version" ]] && version=$NZ_VERSION
    echo -e "安装版本：$version"

    mkdir -p $NZ_DASHBOARD_PATH
    cd $NZ_DASHBOARD_PATH || exit

    echo -e "下载面板二进制..."
    if ! wget -O nezha-dashboard "https://github.com/midoks/nezha/releases/download/${version}/nezha-dashboard-linux-${os_arch}" >/dev/null 2>&1; then
        echo -e "${red}下载面板二进制失败${plain}"
        return 1
    fi
    chmod +x nezha-dashboard

    # 下载并处理 systemd service 文件
    # === 仅此处修改，兼容 midoks 版本，下载失败则写入默认 service 文件 ===
    if ! wget -t 2 -T 10 -O $NZ_DASHBOARD_SERVICE "https://${GITHUB_RAW_URL}/script/nezha-dashboard.service" >/dev/null 2>&1; then
        echo -e "${yellow}未能从远程下载 service 文件，正在使用本地默认模板生成${plain}"
        cat > $NZ_DASHBOARD_SERVICE <<EOF
[Unit]
Description=Nezha Dashboard
After=network.target

[Service]
Type=simple
ExecStart=${NZ_DASHBOARD_PATH}/nezha-dashboard
WorkingDirectory=${NZ_DASHBOARD_PATH}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable nezha

    echo -e "安装完成，尝试启动面板..."
    start_dashboard
}

start_dashboard() {
    # 确保服务文件存在（新增）
    ensure_dashboard_service

    systemctl start nezha
    sleep 2
    if systemctl is-active --quiet nezha; then
        echo -e "${green}面板启动成功${plain}"
    else
        echo -e "${red}面板启动失败，查看日志：journalctl -u nezha -f${plain}"
    fi
}

restart_and_update() {
    # 确保服务文件存在（新增）
    ensure_dashboard_service

    systemctl restart nezha
    sleep 2
    if systemctl is-active --quiet nezha; then
        echo -e "${green}面板重启成功${plain}"
    else
        echo -e "${red}面板重启失败，查看日志：journalctl -u nezha -f${plain}"
    fi
}

install_agent() {
    install_base
    mkdir -p $NZ_AGENT_PATH
    cd $NZ_AGENT_PATH || exit

    # midoks 原始版本使用naiba官方Agent，保持不变
    echo -e "下载Agent二进制..."
    if ! wget -O nezha-agent "https://github.com/naiba/nezha/releases/download/${NZ_VERSION}/nezha-agent-linux-${os_arch}" >/dev/null 2>&1; then
        echo -e "${red}下载Agent失败${plain}"
        return 1
    fi
    chmod +x nezha-agent

    # 创建 agent service
    cat > $NZ_AGENT_SERVICE <<EOF
[Unit]
Description=Nezha Agent
After=network.target

[Service]
Type=simple
ExecStart=${NZ_AGENT_PATH}/nezha-agent
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nezha-agent
    systemctl start nezha-agent
    echo -e "${green}Agent安装并启动成功${plain}"
}

uninstall_all() {
    systemctl stop nezha-agent nezha
    systemctl disable nezha-agent nezha
    rm -rf $NZ_BASE_PATH
    rm -f $NZ_AGENT_SERVICE $NZ_DASHBOARD_SERVICE
    systemctl daemon-reload
    echo -e "${green}已卸载哪吒监控及服务${plain}"
}

show_menu() {
    clear
    echo -e " 哪吒监控 安装脚本 (修改版 修复 .service)"
    echo -e " 1. 安装面板"
    echo -e " 2. 启动面板"
    echo -e " 3. 重启面板"
    echo -e " 4. 安装Agent"
    echo -e " 5. 卸载全部"
    echo -e " 0. 退出"
    echo
    read -e -p "请选择: " num
    case "$num" in
        1) install_dashboard ;;
        2) start_dashboard ;;
        3) restart_and_update ;;
        4) install_agent ;;
        5) uninstall_all ;;
        0) exit 0 ;;
        *) echo -e "${red}请输入正确数字${plain}" && sleep 1 && show_menu ;;
    esac
}

pre_check
show_menu
