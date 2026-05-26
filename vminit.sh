#!/bin/bash
# Author: Tajang
# Email: Tajang@qq.com

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 运行此脚本，例如：sudo bash vminit.sh"
  exit
fi

echo "=== 开始配置 DNS ==="

# 解除 /etc/resolv.conf 的锁定（防止之前被锁过，导致备份或删除失败）
sudo chattr -i /etc/resolv.conf 2>/dev/null

# 1. 备份原来的配置文件
if [ -f /etc/resolv.conf ] || [ -L /etc/resolv.conf ]; then
    sudo cp /etc/resolv.conf /etc/resolv.conf.bak
    echo "已备份 /etc/resolv.conf 到 /etc/resolv.conf.bak"
fi

# 2. 删除默认的 DNS 配置文件
sudo rm -f /etc/resolv.conf

# 3 & 4. 新建并写入新的 DNS 记录
sudo tee /etc/resolv.conf > /dev/null << EOF
nameserver 223.5.5.5
nameserver 119.29.29.29
nameserver 8.8.8.8
EOF
echo "已写入新的 DNS 配置"

# 5. 锁死 /etc/resolv.conf
sudo chattr +i /etc/resolv.conf
echo "/etc/resolv.conf 已被锁死 (chattr +i)"

echo -e "\n=== 开始配置中科大镜像源 ==="

# 检查当前是否已经使用 USTC 源
if ! grep -q "mirrors.ustc.edu.cn" /etc/apt/sources.list 2>/dev/null; then

    echo "开始获取对应网络源 (USTC)..."

    # 检查 wget 是否存在
    if ! command -v wget >/dev/null 2>&1; then
        echo "wget 未安装，开始安装..."
        apt_update_once
        apt-get install -y wget
    fi

    # 获取 Ubuntu 代号
    ubuntu_lsb=$(lsb_release -c -s)
    echo "当前系统代号: ${ubuntu_lsb}"

    # 获取系统架构
    arch=$(dpkg --print-architecture)
    echo "当前系统架构: ${arch}"

    # USTC repogen 地址
    src_url="http://mirrors.ustc.edu.cn/repogen/conf/ubuntu-https-4-${ubuntu_lsb}"

    # 备份原有源
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
    echo "已备份 /etc/apt/sources.list 为 /etc/apt/sources.list.bak"

    # 删除 Deb822 格式源（Ubuntu 24.04+ 常见）
    if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
        sudo rm -f /etc/apt/sources.list.d/ubuntu.sources
        echo "已删除 ubuntu.sources"
    fi

    # 下载源文件到临时文件
    tmp_source="/tmp/ustc.sources.list"

    if wget -qO "$tmp_source" "$src_url"; then

        echo "USTC 源获取成功"

        # ARM 架构修复
        case "$arch" in
            arm64|armhf|ppc64el|s390x|riscv64)
                echo "检测到 ports 架构，修正为 ubuntu-ports 源..."
                sed -i 's#https://mirrors.ustc.edu.cn/ubuntu/#https://mirrors.ustc.edu.cn/ubuntu-ports/#g' "$tmp_source"
                ;;
            *)
                echo "检测到标准架构，使用 ubuntu 主仓库"
                ;;
        esac

        # 写入 sources.list
        sudo cp "$tmp_source" /etc/apt/sources.list

        echo "USTC 源配置成功"

    else
        echo "获取 USTC 源失败，检查网络或 codename: $ubuntu_lsb"
        exit 1
    fi

else
    echo "系统已使用 USTC 源，跳过"
fi

# 禁止大版本升级，也不提示
sudo sed -i 's/^Prompt=.*/Prompt=never/' /etc/update-manager/release-upgrades
echo "已禁止大版本升级，也不提示"

# 更新软件列表
echo "正在执行 apt-get update & upgrade"
apt-get update
apt-get upgrade -y

# 禁止自动更新和弹窗
echo "禁止自动更新和弹窗"
sudo systemctl stop apt-daily.timer apt-daily-upgrade.timer
sudo systemctl disable apt-daily.timer apt-daily-upgrade.timer
sudo systemctl stop apt-daily.service apt-daily-upgrade.service
sudo systemctl disable apt-daily.service apt-daily-upgrade.service

echo "=== 开始下载基础工具 ==="
apt-get -y install git curl net-tools gcc make cmake unzip

echo "=== 开始下载开发环境 ==="
apt-get -y install gcc-multilib

echo "=== 开始下载 vm-tools ==="
sudo apt-get install open-vm-tools-desktop -y
echo "vm-tools已安装，复制功能需重启"

echo -e "\n=== 脚本执行完毕！ ==="