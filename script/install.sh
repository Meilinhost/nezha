#!/bin/bash

#========================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+ / Alpine 3+
#   Description: 哪吒监控安装脚本 - 适配 midoks/nezha 修改版
#   Github: https://github.com/midoks/nezha
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
    
    # check root
    [[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1
    
    ## os_arch
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
    
    ## China_IP
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
        Docker_IMG="ghcr.io/naiba/nezha-dashboard"
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
    new_version=$(grep "NZ_VERSION" /tmp/nezha.sh | head -n 1 | awk -F "=" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
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

install_soft() {
    (command -v yum >/dev/null 2>&1 && yum makecache && yum install $* selinux-policy -y) ||
    (command -v apt >/dev/null 2>&1 && apt update && apt install $* selinux-utils -y) ||
    (command -v pacman >/dev/null 2>&1 && pacman -Syu $* base-devel --noconfirm)  ||
    (command -v apt-get >/dev/null 2>&1 && apt-get update && apt-get install $* selinux-utils -y) ||
    (command -v apk >/dev/null 2>&1 && apk update && apk add $* -f)
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
    
    if [ ! -n "$version" ]; then
        echo -e "获取版本号失败，请检查本机能否链接 https://api.github.com/repos/midoks/nezha/releases/latest"
        return 0
    else
        echo -e "当前最新版本为: ${version}"
    fi
    
    echo -e "> 安装面板"
    
    # 哪吒监控文件夹
    if [ ! -d "${NZ_DASHBOARD_PATH}" ]; then
        mkdir -p $NZ_DASHBOARD_PATH
    else
        echo "您可能已经安装过面板端，重复安装会覆盖数据，请注意备份。"
        read -e -r -p "是否退出安装? [Y/n] " input
        case $input in
            [yY][eE][sS] | [yY])
                echo "退出安装"
                exit 0
            ;;
            [nN][oO] | [nN])
                echo "继续安装"
            ;;
            *)
                echo "退出安装"
                exit 0
            ;;
        esac
    fi
    
    chmod 777 -R $NZ_DASHBOARD_PATH
    
    echo -e "正在安装面板"
    wget -t 2 -T 10 -O nezha-linux-${os_arch}.zip https://${GITHUB_URL}/midoks/nezha/releases/download/${version}/nezha-linux-${os_arch}.zip >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}Release 下载失败，请检查本机能否连接 ${GITHUB_URL}${plain}"
        return 0
    fi

    mv nezha-linux-${os_arch}.zip $NZ_DASHBOARD_PATH
    cd $NZ_DASHBOARD_PATH && unzip -qo nezha-linux-${os_arch}.zip
    rm -rf nezha-linux-${os_arch}.zip

    modify_dashboard_config 0

    # 如果是非 Alpine，则尝试创建或下载 service 文件
    if [ "$os_alpine" != 1 ];then
        if ! wget -t 2 -T 10 -O $NZ_DASHBOARD_SERVICE https://${GITHUB_RAW_URL}/script/nezha-dashboard.service >/dev/null 2>&1; then
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
        systemctl start nezha
    else
        echo "Alpine 系统请手动配置服务或后台运行面板"
    fi

    echo -e "${green}面板安装完成！${plain}"
}

modify_dashboard_config() {
    # 修改配置示例（这里保留示例空函数，用户可根据实际情况添加）
    return 0
}

install_agent() {
    install_base
    
    echo -e "> 安装 Agent"
    # 根据系统架构选择 agent
    local version=$(curl -m 10 -sL "https://api.github.com/repos/midoks/nezha-agent/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$version" ]; then
        version=$NZ_VERSION
    fi
    
    mkdir -p $NZ_AGENT_PATH
    cd $NZ_AGENT_PATH
    
    # 这里用官方 nezhahq agent 下载地址，也可改成 midoks 的私有地址
    wget -t 2 -T 10 https://github.com/nezhahq/agent/releases/download/${version}/nezha-agent-linux-${os_arch}.zip -O nezha-agent.zip >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}Agent 下载失败，请检查网络或镜像${plain}"
        return 0
    fi
    
    unzip -o nezha-agent.zip
    rm -f nezha-agent.zip
    
    # 创建 systemd 服务文件
    cat > $NZ_AGENT_SERVICE <<EOF
[Unit]
Description=Nezha Agent
After=network.target

[Service]
Type=simple
ExecStart=${NZ_AGENT_PATH}/nezha-agent
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nezha-agent
    systemctl start nezha-agent
    
    echo -e "${green}Agent 安装完成！${plain}"
}

uninstall() {
    systemctl stop nezha-agent nezha >/dev/null 2>&1
    systemctl disable nezha-agent nezha >/dev/null 2>&1
    rm -rf $NZ_BASE_PATH
    rm -f $NZ_DASHBOARD_SERVICE $NZ_AGENT_SERVICE
    systemctl daemon-reload
    echo -e "${green}已卸载哪吒监控${plain}"
}

show_menu() {
    clear
    echo -e "哪吒监控 面板与 Agent 一键安装管理脚本\n"
    echo -e " 1. 安装面板"
    echo -e " 2. 安装 Agent"
    echo -e " 3. 卸载"
    echo -e " 4. 更新脚本"
    echo -e " 0. 退出\n"
    echo -n "请输入选择 [0-4]: "
    read -r num
    case "$num" in
        1)
            install_dashboard
            before_show_menu
            ;;
        2)
            install_agent
            before_show_menu
            ;;
        3)
            confirm "确认卸载？" "n" && uninstall
            before_show_menu
            ;;
        4)
            update_script
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${red}请输入正确数字 [0-4]${plain}"
            sleep 2s
            show_menu
            ;;
    esac
}

pre_check
show_menu
