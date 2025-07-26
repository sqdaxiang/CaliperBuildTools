#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 

OS_TYPE=""
OS_VERSION=""

handle_sudo_permission() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi

    echo -e "${RED}❌ 普通用户必须通过sudo执行！请使用命令: sudo bash deploy_caliper.sh${NC}"
    exit 1
}

replace_centos_repo() {
    mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak &> /dev/null || true
    
    if curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo; then
        echo -e "${GREEN}✅ 阿里云YUM源配置成功${NC}"
    else
        echo -e "${YELLOW}⚠️ 阿里云源下载失败，尝试腾讯云源${NC}"
        if curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.cloud.tencent.com/repo/centos7_base.repo; then
            echo -e "${GREEN}✅ 腾讯云YUM源配置成功${NC}"
        else
            echo -e "${RED}❌ 国内YUM源配置失败，请检查网络${NC}"
            exit 1
        fi
    fi
}

# 权限检查
handle_sudo_permission

# 系统检查与识别
check_os() {
    if [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        if [ "$DISTRIB_ID" = "Ubuntu" ]; then
            OS_TYPE="ubuntu"
            OS_VERSION="$DISTRIB_RELEASE"
            echo -e "${YELLOW}=== 确认当前系统：Ubuntu ${OS_VERSION} ===${NC}"
            return 0
        fi
    elif [ -f /etc/centos-release ]; then
        if grep -q "CentOS Linux" /etc/centos-release && grep -q "7" /etc/centos-release; then
            OS_TYPE="centos"
            OS_VERSION="7"
            echo -e "${YELLOW}=== 确认当前系统：CentOS ${OS_VERSION} ===${NC}"
            return 0
        fi
    fi
    echo -e "${RED}此脚本仅支持Ubuntu和CentOS 7系统${NC}"
    exit 1
}

# 依赖检查函数
check_dependency() {
    local dep=$1
    local centos_dep=$2

    if [ "$OS_TYPE" = "centos" ] && [ -n "$centos_dep" ]; then
        dep=$centos_dep
    fi

    if ! command -v $dep &> /dev/null; then
        echo -e "${YELLOW}安装依赖 $dep...${NC}"
        if [ "$OS_TYPE" = "ubuntu" ]; then
            apt install -y $dep || { echo -e "${RED}依赖 $dep 安装失败！${NC}"; exit 1; }
        else
            yum install -y $dep || { echo -e "${RED}依赖 $dep 安装失败！${NC}"; exit 1; }
        fi
    else
        echo -e "${GREEN}依赖 $dep 已存在${NC}"
    fi
}

# 统一的镜像检查与加载函数
handle_docker_image() {
    local target_image=$1
    local local_tar_path=$2
    local image_dir=$(dirname "$local_tar_path")

    echo -e "${YELLOW}=== 处理镜像: $target_image ===${NC}"

    if [ ! -d "$image_dir" ]; then
        echo -e "${RED}❌ 镜像目录 $image_dir 不存在，请创建该目录并放入镜像文件${NC}"
        exit 1
    fi

    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${target_image}$"; then
        echo -e "${GREEN}✅ 本地已存在目标镜像: $target_image${NC}"
        return 0
    fi

    echo -e "${YELLOW}本地未找到目标镜像，尝试拉取: $target_image${NC}"
    if docker pull "$target_image"; then
        echo -e "${GREEN}✅ 官方镜像拉取成功${NC}"
        return 0
    fi

    echo -e "${YELLOW}⚠️ 官方镜像拉取失败，尝试加载本地镜像: $local_tar_path${NC}"
    if [ ! -f "$local_tar_path" ]; then
        echo -e "${RED}❌ 本地镜像文件 $local_tar_path 不存在，无法加载${NC}"
        exit 1
    fi

    if ! docker load -i "$local_tar_path"; then
        echo -e "${RED}❌ 本地镜像加载失败: $local_tar_path${NC}"
        exit 1
    fi

    local loaded_image=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -i "$(echo "$target_image" | cut -d: -f1)" | head -n1)
    if [ -z "$loaded_image" ]; then
        echo -e "${RED}❌ 加载的本地镜像无法匹配目标镜像: $target_image${NC}"
        exit 1
    fi

    if [ "$loaded_image" != "$target_image" ]; then
        docker tag "$loaded_image" "$target_image"
    fi

    echo -e "${GREEN}✅ 本地镜像加载并配置成功${NC}"
    return 0
}

# 主流程开始
check_os

# 针对CentOS 7系统更换国内YUM源
if [ "$OS_TYPE" = "centos" ] && [ "$OS_VERSION" = "7" ]; then
    replace_centos_repo
fi

# 脚本目录配置
SCRIPT_DIR=$(cd "$(dirname "$0")" &>/dev/null && pwd)
sudo chown -R "$(logname)":"$(logname)" "$SCRIPT_DIR" 
sudo chmod -R 755 "$SCRIPT_DIR"

# 工作目录配置
IMAGE_DIR="${SCRIPT_DIR}/images"
echo -e "${YELLOW}=== 脚本工作目录：$SCRIPT_DIR ===${NC}"
echo -e "${YELLOW}=== 镜像文件目录：$IMAGE_DIR ===${NC}"

# 安装系统依赖
echo -e "${YELLOW}=== 检查系统核心依赖 ===${NC}"
if [ "$OS_TYPE" = "ubuntu" ]; then
    dependencies=(
        "make" "g++" "gcc" "git" "curl" "wget"
        "apt-transport-https" "ca-certificates"
        "software-properties-common" "build-essential" "libssl-dev"
    )
    for dep in "${dependencies[@]}"; do
        check_dependency $dep
    done
else
    # CentOS 7依赖映射
    dependencies=(
        "make" ""
        "g++" "gcc-c++"
        "gcc" ""
        "git" ""
        "curl" ""
        "wget" ""
        "apt-transport-https" "epel-release"  
        "ca-certificates" ""
        "software-properties-common" "yum-utils"  
        "build-essential" "gcc-c++" 
        "libssl-dev" "openssl-devel" 
    )
    for ((i=0; i<${#dependencies[@]}; i+=2)); do
        dep=${dependencies[i]}
        centos_dep=${dependencies[i+1]}
        check_dependency "$dep" "$centos_dep"
    done
    check_dependency "policycoreutils-python"
fi

# 检查并安装Docker
echo -e "${YELLOW}=== 检查Docker环境 ===${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker未安装，开始安装（阿里云源）...${NC}"
    if [ "$OS_TYPE" = "ubuntu" ]; then
        apt-key del 0EBFCD88 > /dev/null 2>&1 || true
        curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | apt-key add -
        add-apt-repository "deb [arch=amd64] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" -y
        apt update -y --fix-missing
        apt install -y docker-ce docker-ce-cli containerd.io || { echo -e "${RED}Docker安装失败！${NC}"; exit 1; }
    else
        yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io || { echo -e "${RED}Docker安装失败！${NC}"; exit 1; }
    fi
    systemctl start docker && systemctl enable docker
    usermod -aG docker "$(logname)"  
else
    echo -e "${GREEN}Docker已安装${NC}"
    docker --version
fi

# 离线安装Docker Compose
echo -e "${YELLOW}=== 离线安装 Docker Compose ===${NC}"
COMPOSE_FILE="/usr/local/bin/docker-compose"
LOCAL_COMPOSE="$SCRIPT_DIR/bin/docker-compose-linux-x86_64"

if command -v docker-compose &>/dev/null; then
    current_version=$(docker-compose --version | awk '{print $3}' | cut -d',' -f1)
    echo -e "${GREEN}ℹ️ Docker Compose已安装，当前版本：$current_version${NC}"
else
    echo -e "${YELLOW}ℹ️ 未检测到Docker Compose，开始离线安装...${NC}"

    if cp "$LOCAL_COMPOSE" "$COMPOSE_FILE"; then
        chmod +x "$COMPOSE_FILE"
        
        if command -v docker-compose &>/dev/null; then
            installed_version=$(docker-compose --version | awk '{print $3}' | cut -d',' -f1)
            echo -e "${GREEN}✅ Docker Compose安装成功！版本：$installed_version${NC}"
        else
            echo -e "${RED}❌ 安装失败：文件已复制，但无法识别docker-compose命令${NC}"
            echo -e "${RED}   检查：/usr/local/bin是否在PATH中？执行 echo $PATH 确认${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ 安装失败：无法复制文件到$COMPOSE_FILE${NC}"
        exit 1
    fi
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
NVM_DIR="/usr/local/nvm"  
NVM_VERSION="v0.33.2"    
NVM_REPO_GITHUB="https://github.com/nvm-sh/nvm.git"
NVM_REPO_GITEE="https://gitee.com/mirrors/nvm.git"

# 确保目录权限
mkdir -p "$NVM_DIR"
chmod -R 775 "$NVM_DIR"
chown -R "$USER:$USER" "$NVM_DIR" 

if [ -s "$NVM_DIR/nvm.sh" ]; then
    \. "$NVM_DIR/nvm.sh"
fi

if command -v nvm &> /dev/null && nvm --version &> /dev/null; then
    echo -e "${GREEN}NVM已安装（版本：$(nvm --version)）${NC}"
else
    echo -e "${YELLOW}NVM未安装或无效，开始安装/修复...${NC}"
    if [ -d "$NVM_DIR" ]; then
        rm -rf "$NVM_DIR"
        mkdir -p "$NVM_DIR"
        chown -R "$USER:$USER" "$NVM_DIR"
    fi
    
    echo -e "${YELLOW}尝试从GitHub克隆NVM仓库...${NC}"
    if ! git clone --branch "$NVM_VERSION" "$NVM_REPO_GITHUB" "$NVM_DIR"; then
        echo -e "${YELLOW}GitHub克隆失败，尝试Gitee镜像...${NC}"
        if ! git clone --branch "$NVM_VERSION" "$NVM_REPO_GITEE" "$NVM_DIR"; then
            echo -e "${RED}Gitee克隆也失败！NVM安装失败${NC}"
            exit 1
        fi
    fi
    
    # 配置全局环境变量
    echo "export NVM_DIR=\"$NVM_DIR\"" >> /etc/profile.d/nvm.sh
    echo "[ -s \"$NVM_DIR/nvm.sh\" ] && \. \"$NVM_DIR/nvm.sh\"" >> /etc/profile.d/nvm.sh
    chmod +x /etc/profile.d/nvm.sh
    \. /etc/profile.d/nvm.sh  
    
    if ! command -v nvm &> /dev/null; then
        echo -e "${RED}NVM配置失败${NC}"
        exit 1
    fi
    echo -e "${GREEN}NVM安装成功（版本：$(nvm --version)）${NC}"
fi

# 安装Node.js 8
echo -e "${YELLOW}=== 安装Node.js 8 ===${NC}"
NODE8_VERSION="8.17.0"
NODE8_CACHE_DIR="$NVM_DIR/.cache/bin/node-v${NODE8_VERSION}-linux-x64"
rm -rf "$NODE8_CACHE_DIR"
export NVM_NODEJS_ORG_MIRROR="https://mirrors.aliyun.com/nodejs-release"
if ! nvm ls 8 &> /dev/null; then
    echo -e "${YELLOW}Node.js 8未安装，开始安装...${NC}"
    MAX_RETRIES=100
    RETRY_COUNT=0
    INSTALL_SUCCESS=0
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if nvm install "$NODE8_VERSION"; then
            INSTALL_SUCCESS=1
            break
        else
            echo -e "${RED}安装失败,等待2秒后重试...${NC}"
            rm -rf "$NODE8_CACHE_DIR"
            RETRY_COUNT=$((RETRY_COUNT + 1))
            sleep 2
        fi
    done

    if [ $INSTALL_SUCCESS -ne 1 ]; then
        echo -e "${RED}已达最大重试次数，Node.js $NODE8_VERSION 安装失败，请尝试重新运行脚本${NC}"
        exit 1
    fi
else
    nvm use "$NODE8_VERSION"
fi
nvm alias default "$NODE8_VERSION"
echo -e "${GREEN}当前Node版本：$(node -v)${NC}"
echo -e "${GREEN}当前npm版本：$(npm -v)${NC}"

# 工作目录配置
WORK_DIR="$SCRIPT_DIR/caliper-workspace"
echo -e "${YELLOW}=== 准备工作目录：$WORK_DIR ===${NC}"

# 先删除旧目录
if [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR" || { echo -e "${RED}❌ 无法删除旧工作目录${NC}"; exit 1; }
fi

# 重新创建目录并立即设置权限
mkdir -p "$WORK_DIR" || { echo -e "${RED}❌ 无法创建工作目录${NC}"; exit 1; }
chown -R "$(logname)":"$(logname)" "$WORK_DIR"  
chmod -R 775 "$WORK_DIR"                       
cd "$WORK_DIR" || { echo -e "${RED}❌ 无法进入工作目录${NC}"; exit 1; }
echo -e "${GREEN}✅ 工作目录准备完成${NC}"

# 配置npm国内镜像
echo -e "${YELLOW}=== 配置npm国内镜像 ===${NC}"
# 先以root身份配置全局镜像
npm config set registry https://registry.npmmirror.com
npm config set disturl https://npmmirror.com/dist

# 配置npm缓存目录
NPM_CACHE_DIR="${WORK_DIR}/.npm-cache"
mkdir -p "$NPM_CACHE_DIR"
chown -R "$(logname)":"$(logname)" "$NPM_CACHE_DIR"
chmod -R 775 "$NPM_CACHE_DIR"
npm config set cache "$NPM_CACHE_DIR"

# 初始化NPM项目
echo -e "${YELLOW}初始化NPM项目...${NC}"
sudo -u "$(logname)" bash -c "\
    source /etc/profile.d/nvm.sh && \
    nvm use 8 > /dev/null 2>&1 && \
    npm init -y --silent" || { 
    echo -e "${RED}❌ NPM项目初始化失败${NC}"; exit 1; 
}

# 安装caliper-cli
echo -e "${YELLOW}=== 安装caliper-cli@0.2.0 ===${NC}"
MAX_RETRIES=100
RETRY_DELAY=2
RETRY_COUNT=0
INSTALL_SUCCESS=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    sudo -u "$(logname)" bash -c "\
        source /etc/profile.d/nvm.sh && \
        nvm use 8 > /dev/null 2>&1 && \
        npm install --only=prod @hyperledger/caliper-cli@0.2.0" && {
        INSTALL_SUCCESS=1
        break
    }

    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo -e "${YELLOW}⚠️ caliper-cli安装失败，${RETRY_DELAY}秒后重试...${NC}"
        sudo -u "$(logname)" bash -c "\
            source /etc/profile.d/nvm.sh && \
            nvm use 8 > /dev/null 2>&1 && \
            rm -rf node_modules/@hyperledger/caliper-cli && \
            npm cache clean --force"
        sleep $RETRY_DELAY
    fi
done

if [ $INSTALL_SUCCESS -ne 1 ]; then
    echo -e "${RED}❌ 已达到最大重试次数（${MAX_RETRIES}次），caliper-cli安装失败，请检查网络后重新运行脚本${NC}"
    exit 1
fi

# 验证caliper版本
sudo -u "$(logname)" bash -c "\
    source /etc/profile.d/nvm.sh && \
    nvm use 8 > /dev/null 2>&1 && \
    npx caliper --version" || { 
    echo -e "${RED}❌ caliper-cli无效${NC}"; exit 1; 
}

# 配置Git临时目录权限
GIT_TMP_DIR="${WORK_DIR}/.git-tmp"
mkdir -p "$GIT_TMP_DIR"
chown -R "$(logname)":"$(logname)" "$GIT_TMP_DIR"
chmod -R 775 "$GIT_TMP_DIR"
git config --global core.tempdir "$GIT_TMP_DIR"

# 绑定FISCO BCOS
echo -e "${YELLOW}=== 绑定FISCO BCOS ===${NC}"
MAX_RETRIES=100
RETRY_DELAY=2
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    sudo -u "$(logname)" bash -c "\
        source /etc/profile.d/nvm.sh && \
        nvm use 8 > /dev/null 2>&1 && \
        cd $WORK_DIR && \
        npx caliper bind --caliper-bind-sut fisco-bcos --caliper-bind-sdk latest" && {
        echo -e "${GREEN}✅ FISCO BCOS绑定成功${NC}"
        break
    }

    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo -e "${YELLOW}⚠️ 绑定失败，${RETRY_DELAY}秒后重试...${NC}"
        sleep $RETRY_DELAY
    else
        echo -e "${RED}❌ 已达到最大重试次数，绑定失败${NC}"
        exit 1
    fi
done


# 下载测试案例
echo -e "${YELLOW}=== 下载测试案例 ===${NC}"
if [ ! -d "caliper-benchmarks" ]; then
    if ! git clone https://github.com/vita-dounai/caliper-benchmarks.git; then
        echo -e "${YELLOW}GitHub克隆失败，尝试Gitee...${NC}"
        if ! git clone https://gitee.com/vita-dounai/caliper-benchmarks.git; then
            echo -e "${RED}测试案例下载失败！${NC}"; exit 1
        fi
    fi
else
    echo -e "${GREEN}测试案例已存在${NC}"
fi

# 修改配置文件
echo -e "${YELLOW}=== 修改配置文件 ===${NC}"

FILE="$WORK_DIR/node_modules/@hyperledger/caliper-fisco-bcos/lib/fiscoBcos.js"
if [ ! -f "$FILE" ]; then
    echo -e "${RED}❌ 未找到文件: $FILE${NC}"
    exit 1
fi
sed -i "s#const Color = require('./common');#const Color = require('./common').Color;#" "$FILE"
sed -i '/this\.fiscoBcosSettings = CaliperUtils\.parseYaml(this\.configPath)\['\''fisco-bcos'\''\];/a \    if (this.fiscoBcosSettings.network && this.fiscoBcosSettings.network.authentication) {\n        for (let k in this.fiscoBcosSettings.network.authentication) {\n            this.fiscoBcosSettings.network.authentication[k] = CaliperUtils.resolvePath(this.fiscoBcosSettings.network.authentication[k], workspace_root);\n        }\n    }' "$FILE"
sed -i "s#const fiscoBcosSettings = CaliperUtils.parseYaml(this.configPath)\['fisco-bcos'\];#const fiscoBcosSettings = this.fiscoBcosSettings;#" "$FILE"

FILE="$WORK_DIR/node_modules/@hyperledger/caliper-fisco-bcos/lib/channelPromise.js"
if [ ! -f "$FILE" ]; then
    echo -e "${RED}❌ 未找到文件: $FILE${NC}"
    exit 1
fi
sed -i "s#let emitter = emitters.get(seq)\.emitter;#let emitter = emitters.get(seq);\n    if(!emitter) {\n        return;\n    }\n    emitter = emitter.emitter;#" "$FILE"

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
    chown "$(logname)":"$(logname)" package.json
fi

# 重新安装依赖
echo -e "${YELLOW}=== 重新安装依赖... ===${NC}"
MAX_RETRIES=100
RETRY_DELAY=2
RETRY_COUNT=0
SUCCESS=0

set +e

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    sudo -u "$(logname)" bash -c "\
        source /etc/profile.d/nvm.sh && \
        nvm use 8 > /dev/null 2>&1 && \
        export PATH=\"$NVM_DIR/versions/node/v8.17.0/bin:\$PATH\" && \
        npm install --no-fund"
    
    # 检查命令执行结果
    if [ $? -eq 0 ]; then
        SUCCESS=1
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo -e "${YELLOW}⚠️ 依赖安装失败，${RETRY_DELAY}秒后重试 ${NC}"
        sleep $RETRY_DELAY
        sudo -u "$(logname)" bash -c "\
            source /etc/profile.d/nvm.sh && \
            nvm use 8 > /dev/null 2>&1 && \
            export PATH=\"$NVM_DIR/versions/node/v8.17.0/bin:\$PATH\" && \
            rm -rf node_modules package-lock.json && \
            npm cache clean --force"
    fi
done

# 恢复set -e
set -e

if [ $SUCCESS -ne 1 ]; then
    echo -e "${RED}❌ 已达到最大重试次数，依赖安装失败${NC}"
    echo -e "${YELLOW}请检查网络连接或手动配置GitHub镜像后重试${NC}"
    exit 1
fi

# 回到工作目录
cd "$WORK_DIR" || exit 1

# 执行HelloWorld测试
echo -e "${YELLOW}=== 执行HelloWorld合约测试 ===${NC}"

npx caliper benchmark run \
    --caliper-workspace caliper-benchmarks \
    --caliper-benchconfig benchmarks/samples/fisco-bcos/helloworld/config.yaml \
    --caliper-networkconfig networks/fisco-bcos/4nodes1group/fisco-bcos.json \
    || { echo -e "${RED}测试执行失败${NC}"; exit 1; }

echo -e "${GREEN}=== 所有操作完成，环境搭建成功！ ===${NC}"
echo -e "${GREEN}工作目录：$WORK_DIR${NC}"
