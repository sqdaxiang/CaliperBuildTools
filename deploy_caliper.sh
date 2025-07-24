#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 

SUDOERS_MODIFIED=false

# 配置sudo免密权限
configure_sudo_nopasswd() {
    if ! sudo grep -q "$USER ALL=(ALL) NOPASSWD: ALL" /etc/sudoers; then
        echo -e "${YELLOW}配置sudo免密权限（临时）...${NC}"
        echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo EDITOR='tee -a' visudo > /dev/null 2>&1
        SUDOERS_MODIFIED=true
    fi
}

# 恢复sudo配置
restore_sudoers() {
    if [ "$SUDOERS_MODIFIED" = "true" ]; then
        echo -e "${YELLOW}恢复sudo权限配置...${NC}"
        sudo sed -i "/$USER ALL=(ALL) NOPASSWD: ALL/d" /etc/sudoers > /dev/null 2>&1
    fi
}
trap restore_sudoers EXIT

# 系统检查
if [ ! -f /etc/lsb-release ]; then
    echo -e "${RED}此脚本仅支持Ubuntu系统${NC}"
    exit 1
fi
. /etc/lsb-release
if [ "$DISTRIB_ID" != "Ubuntu" ]; then
    echo -e "${RED}检测到非Ubuntu系统（${DISTRIB_ID}）${NC}"
    exit 1
fi
echo -e "${YELLOW}=== 确认当前系统：Ubuntu ${DISTRIB_RELEASE} ===${NC}"

# 配置sudo免密
configure_sudo_nopasswd

# 工作目录
SCRIPT_DIR=$(cd $(dirname $0); pwd)
# 定义镜像存放目录
IMAGE_DIR="${SCRIPT_DIR}/images"
echo -e "${YELLOW}=== 脚本工作目录：$SCRIPT_DIR ===${NC}"
echo -e "${YELLOW}=== 镜像文件目录：$IMAGE_DIR ===${NC}"

# 依赖检查函数
check_dependency() {
    local dep=$1
    if ! command -v $dep &> /dev/null; then
        echo -e "${YELLOW}安装依赖 $dep...${NC}"
        sudo apt install -y $dep || { echo -e "${RED}依赖 $dep 安装失败！${NC}"; exit 1; }
    else
        echo -e "${GREEN}依赖 $dep 已存在${NC}"
    fi
}

# 统一的镜像检查与加载函数
handle_docker_image() {
    local target_image=$1       # 目标镜像（如fiscoorg/fiscobcos:latest）
    local local_tar_path=$2     # 本地镜像tar包路径
    local image_dir=$(dirname "$local_tar_path")  # 镜像目录

    echo -e "${YELLOW}=== 处理镜像: $target_image ===${NC}"

    # 检查镜像目录是否存在
    if [ ! -d "$image_dir" ]; then
        echo -e "${RED}❌ 镜像目录 $image_dir 不存在，请创建该目录并放入镜像文件${NC}"
        exit 1
    fi

    # 检查本地是否已存在目标镜像
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${target_image}$"; then
        echo -e "${GREEN}✅ 本地已存在目标镜像: $target_image${NC}"
        return 0
    fi

    # 本地不存在，尝试拉取官方镜像
    echo -e "${YELLOW}本地未找到目标镜像，尝试拉取: $target_image${NC}"
    if docker pull "$target_image"; then
        echo -e "${GREEN}✅ 官方镜像拉取成功${NC}"
        return 0
    fi

    # 拉取失败，尝试加载本地tar包
    echo -e "${YELLOW}⚠️ 官方镜像拉取失败，尝试加载本地镜像: $local_tar_path${NC}"
    if [ ! -f "$local_tar_path" ]; then
        echo -e "${RED}❌ 本地镜像文件 $local_tar_path 不存在，无法加载${NC}"
        exit 1
    fi

    # 加载本地镜像并校验标签
    if ! docker load -i "$local_tar_path"; then
        echo -e "${RED}❌ 本地镜像加载失败: $local_tar_path${NC}"
        exit 1
    fi

    # 提取加载后的镜像名（处理可能的标签不一致问题）
    local loaded_image=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -i "$(echo "$target_image" | cut -d: -f1)" | head -n1)
    if [ -z "$loaded_image" ]; then
        echo -e "${RED}❌ 加载的本地镜像无法匹配目标镜像: $target_image${NC}"
        exit 1
    fi

    # 统一标签为目标镜像名
    if [ "$loaded_image" != "$target_image" ]; then
        docker tag "$loaded_image" "$target_image"
    fi

    echo -e "${GREEN}✅ 本地镜像加载并配置成功${NC}"
    return 0
}

# 安装系统依赖
echo -e "${YELLOW}=== 检查系统核心依赖 ===${NC}"
dependencies=("make" "g++" "gcc" "git" "curl" "wget" "apt-transport-https" "ca-certificates" "software-properties-common" "build-essential" "libssl-dev")
for dep in "${dependencies[@]}"; do
    check_dependency $dep
done

# 检查并安装Docker
echo -e "${YELLOW}=== 检查Docker环境 ===${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker未安装，开始安装（阿里云源）...${NC}"
    # 彻底清理旧的Docker GPG密钥
    sudo apt-key del 0EBFCD88 > /dev/null 2>&1 || true
    # 添加阿里云Docker源
    curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" -y
    # 更新源并安装Docker
    sudo apt update -y --fix-missing
    sudo apt install -y docker-ce docker-ce-cli containerd.io || { echo -e "${RED}Docker安装失败！${NC}"; exit 1; }
    sudo systemctl start docker && sudo systemctl enable docker
    sudo usermod -aG docker $USER
    echo -e "${YELLOW}Docker安装完成！注意：Docker权限变更需重新登录生效${NC}"
else
    echo -e "${GREEN}Docker已安装${NC}"
    docker --version
fi

# 离线安装Docker Compose
echo -e "${YELLOW}=== 离线安装 Docker Compose ===${NC}"
COMPOSE_FILE="/usr/local/bin/docker-compose"
LOCAL_COMPOSE="$SCRIPT_DIR/bin/docker-compose-Linux-x86_64"

if [ ! -f "$LOCAL_COMPOSE" ]; then
    echo -e "${RED}❌ 未找到本地 docker-compose 文件：$LOCAL_COMPOSE${NC}"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}从本地文件安装 docker-compose...${NC}"
    sudo cp "$LOCAL_COMPOSE" "$COMPOSE_FILE"
    sudo chmod +x "$COMPOSE_FILE"
    sudo ln -sf "$COMPOSE_FILE" /usr/bin/docker-compose
else
    echo -e "${GREEN}Docker Compose已安装${NC}"
fi

if ! docker-compose --version &> /dev/null; then
    echo -e "${RED}❌ Docker Compose 安装失败！${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Docker Compose 安装成功：$(docker-compose --version)${NC}"
fi

# 处理FISCO BCOS镜像
handle_docker_image \
    "fiscoorg/fiscobcos:latest" \
    "${IMAGE_DIR}/fiscobcos.tar"

# 处理Solidity编译器镜像
handle_docker_image \
    "ethereum/solc:0.4.25" \
    "${IMAGE_DIR}/solc-0.4.25.tar"

# 安装NVM
echo -e "${YELLOW}=== 安装NVM ===${NC}"
NVM_DIR="$HOME/.nvm"
NVM_VERSION="v0.33.2"
NVM_REPO_GITHUB="https://github.com/creationix/nvm.git"
NVM_REPO_GITEE="https://gitee.com/mirrors/nvm.git"

if [ -s "$NVM_DIR/nvm.sh" ]; then
    \. "$NVM_DIR/nvm.sh"
fi

if command -v nvm &> /dev/null && nvm --version &> /dev/null; then
    echo -e "${GREEN}NVM已安装（版本：$(nvm --version)）${NC}"
else
    echo -e "${YELLOW}NVM未安装或无效，开始安装/修复...${NC}"
    if [ -d "$NVM_DIR" ]; then
        echo -e "${YELLOW}清理残留的NVM目录...${NC}"
        rm -rf "$NVM_DIR"
    fi
    
    echo -e "${YELLOW}尝试从GitHub克隆NVM仓库...${NC}"
    if ! git clone --branch "$NVM_VERSION" "$NVM_REPO_GITHUB" "$NVM_DIR"; then
        echo -e "${YELLOW}GitHub克隆失败，尝试Gitee镜像...${NC}"
        if ! git clone --branch "$NVM_VERSION" "$NVM_REPO_GITEE" "$NVM_DIR"; then
            echo -e "${RED}Gitee克隆也失败！NVM安装失败${NC}"
            exit 1
        fi
    fi
    
    echo -e "${YELLOW}配置NVM环境...${NC}"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    if ! command -v nvm &> /dev/null || ! nvm --version &> /dev/null; then
        echo -e "${RED}NVM配置失败${NC}"
        exit 1
    fi
    echo -e "${GREEN}NVM安装成功（版本：$(nvm --version)）${NC}"
fi

# 安装Node.js 8
echo -e "${YELLOW}=== 安装Node.js 8 ===${NC}"
if ! nvm ls 8 &> /dev/null; then
    echo -e "${YELLOW}Node.js 8未安装，开始安装...${NC}"
    if ! nvm install 8; then
        echo -e "${RED}Node.js 8安装失败！${NC}"
        exit 1
    fi
else
    nvm use 8
fi
nvm alias default 8
echo -e "${GREEN}当前Node版本：$(node -v)${NC}"
echo -e "${GREEN}当前npm版本：$(npm -v)${NC}"

# 配置npm国内镜像
echo -e "${YELLOW}=== 配置npm国内镜像 ===${NC}"
npm config set registry https://registry.npmmirror.com
npm config set disturl https://npmmirror.com/dist

# 初始化工作目录
WORK_DIR="$SCRIPT_DIR/caliper-workspace"
sudo rm -rf "$WORK_DIR"  # 清理旧目录避免冲突
mkdir -p "$WORK_DIR" && cd "$WORK_DIR"
echo -e "${YELLOW}=== 工作目录：$WORK_DIR ===${NC}"

# 初始化NPM项目
echo -e "${YELLOW}初始化NPM项目...${NC}"
npm init -y --silent

# 安装指定版本的caliper-cli
echo -e "${YELLOW}=== 安装caliper-cli@0.2.0 ===${NC}"
npm install --only=prod @hyperledger/caliper-cli@0.2.0 || { echo -e "${RED}caliper-cli安装失败${NC}"; exit 1; }
npx caliper --version || { echo -e "${RED}caliper-cli无效${NC}"; exit 1; }

# 绑定FISCO BCOS
echo -e "${YELLOW}=== 绑定FISCO BCOS ===${NC}"
npx caliper bind --caliper-bind-sut fisco-bcos --caliper-bind-sdk latest || { 
    echo -e "${RED}绑定失败，尝试手动安装适配器...${NC}"
    # 手动安装FISCO BCOS适配器
    npm install @hyperledger/caliper-fisco-bcos || { echo -e "${RED}适配器安装失败${NC}"; exit 1; }
}

# 下载测试案例
echo -e "${YELLOW}=== 下载测试案例 ===${NC}"
if [ ! -d "caliper-benchmarks" ]; then
    if ! git clone https://github.com/vita-dounai/caliper-benchmarks.git; then
        echo -e "${YELLOW}GitHub克隆失败，尝试Gitee...${NC}"
        if ! git clone https://gitee.com/vita-dounai/caliper-benchmarks.git; then
            echo -e "${RED}测试案例下载失败！请手动克隆仓库${NC}"; exit 1
        fi
    fi
else
    echo -e "${GREEN}测试案例已存在${NC}"
fi

# 修改配置文件
echo -e "${YELLOW}=== 修改配置文件 ===${NC}"

# 处理 fiscoBcos.js
FILE="$WORK_DIR/node_modules/@hyperledger/caliper-fisco-bcos/lib/fiscoBcos.js"
if [ ! -f "$FILE" ]; then
    echo -e "${RED}❌ 未找到文件: $FILE${NC}"
    exit 1
fi
sed -i "s#const Color = require('./common');#const Color = require('./common').Color;#" "$FILE"
sed -i "/this\.fiscoBcosSettings = CaliperUtils\.parseYaml(this\.configPath)\['fisco-bcos'\];/a \    if (this.fiscoBcosSettings.network && this.fiscoBcosSettings.network.authentication) {\n        for (let k in this.fiscoBcosSettings.network.authentication) {\n            this.fiscoBcosSettings.network.authentication[k] = CaliperUtils.resolvePath(this.fiscoBcosSettings.network.authentication[k], workspace_root);\n        }\n    }"  "$FILE"
sed -i "s#const fiscoBcosSettings = CaliperUtils.parseYaml(this.configPath)\['fisco-bcos'\];#const fiscoBcosSettings = this.fiscoBcosSettings;#" "$FILE"

# 处理 channelPromise.js
FILE="$WORK_DIR/node_modules/@hyperledger/caliper-fisco-bcos/lib/channelPromise.js"
if [ ! -f "$FILE" ]; then
    echo -e "${RED}❌ 未找到文件: $FILE${NC}"
    exit 1
fi
sed -i "s#let emitter = emitters.get(seq)\.emitter;#let emitter = emitters.get(seq);\n    if(!emitter) {\n        return;\n    }\n    emitter = emitter.emitter;#" "$FILE"

# 处理 web3sync.js
FILE="$WORK_DIR/node_modules/@hyperledger/caliper-fisco-bcos/lib/web3lib/web3sync.js" 
if [ ! -f "$FILE" ]; then
    echo -e "${RED}❌ 未找到文件: $FILE${NC}"
    exit 1
fi 
sed -i "s#uuid = uuid.replace(/-/g, '');#uuid = '0x' + uuid.replace(/-/g, '');#" "$FILE"
sed -i "s#extraData: ''#extraData: '0x0'#g" "$FILE"

# 修复secp256k1依赖
cd "$WORK_DIR/node_modules/@hyperledger/caliper-fisco-bcos/" || {
    echo -e "${RED}❌ 切换目录失败${NC}"
    exit 1
}


if ! grep -q '"secp256k1"' package.json; then
    check_dependency jq
    jq '.dependencies["secp256k1"] = "^3.8.0"' package.json > temp.json && mv temp.json package.json
fi


# 重新安装依赖
echo -e "${YELLOW}重新安装依赖...${NC}"
npm install --no-fund || { echo -e "${RED}依赖安装失败${NC}"; exit 1; }
cd "$WORK_DIR"

# 执行HelloWorld测试
echo -e "${YELLOW}=== 执行HelloWorld合约测试 ===${NC}"
npx caliper benchmark run \
    --caliper-workspace caliper-benchmarks \
    --caliper-benchconfig benchmarks/samples/fisco-bcos/helloworld/config.yaml \
    --caliper-networkconfig networks/fisco-bcos/4nodes1group/fisco-bcos.json || { echo -e "${RED}测试执行失败${NC}"; exit 1; }

echo -e "${GREEN}=== 所有操作完成，环境搭建成功！ ===${NC}"
echo -e "${GREEN}工作目录：$WORK_DIR${NC}"