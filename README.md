# Hyperledger Caliper 一键测试环境部署脚本

## 脚本概述
这是一个针对 FISCO BCOS 区块链平台的 Hyperledger Caliper 测试环境自动化部署脚本。通过全流程自动化操作，实现从系统环境检查、依赖安装到测试框架搭建及测试执行的完整部署，极大简化手动配置复杂度。

**适用系统**：已在 **Ubuntu 20.04** 和 **CentOS 7** 系统测试通过，其他系统版本可能存在兼容性问题。


## 核心功能
1. **环境校验**
   - 自动识别系统类型（Ubuntu/CentOS 7）并适配对应操作
   - 确保脚本以 root 或 sudo 权限运行
   - 验证工作目录及镜像存放目录有效性
   - 检查并配置 sudo 免密权限（临时生效，脚本结束后自动恢复）

2. **依赖管理**
   - 自动安装系统核心依赖（make、gcc、git、curl 等），区分 Ubuntu/CentOS 包名差异
   - 配置 Docker 环境（使用阿里云源加速安装，支持 CentOS 7 容器服务适配）
   - 离线安装 Docker Compose（需提前准备二进制文件，支持直接复制无需软链接）

3. **镜像管理**
   - 自动检查并拉取 FISCO BCOS 相关镜像（fiscoorg/fiscobcos、ethereum/solc 等）
   - 拉取失败时自动加载本地镜像文件（支持离线环境，需放在指定 images 目录）
   - 统一镜像标签确保兼容性，支持版本映射处理

4. **Node.js 环境配置**
   - 安装 NVM（Node 版本管理器），支持 GitHub/Gitee 双源克隆（解决网络问题）
   - 安装 Node.js 8 及对应 npm 版本（适配 Caliper 0.2.0 依赖）
   - 配置 npm 国内镜像（npmmirror.com）加速依赖下载

5. **Caliper 部署**
   - 安装指定版本的 Caliper CLI（0.2.0）
   - 绑定 FISCO BCOS 适配器（支持自动重试机制，解决网络波动导致的安装失败）
   - 拉取测试案例仓库（支持 GitHub/Gitee 双源切换，确保仓库可访问）

6. **兼容性修复**
   - 自动修改配置文件解决路径解析问题（适配 CentOS 7 路径格式）
   - 修复事件发射器空值及 UUID 格式兼容问题
   - 补充 secp256k1 密码学依赖库，处理版本兼容性（适配 Node.js 8）

7. **自动化测试**
   - 执行 HelloWorld 合约测试验证环境有效性
   - 输出详细部署结果及工作目录信息，支持超时控制


## 使用方法

### 前置准备
1. 将脚本保存为 `deploy_caliper.sh`
2. 在脚本同级目录创建以下结构：
   ```
   ├── bin/
   │   └── docker-compose-Linux-x86_64  # Docker Compose 二进制文件（需与系统架构匹配）
   └── images/
       ├── fiscobcos.tar                # FISCO BCOS 镜像（可选，离线环境必备）
       └── solc-0.4.25.tar              # Solidity 编译器镜像（可选，离线环境必备）
   ```

### 启动命令
```bash
# 赋予执行权限
chmod +x deploy_caliper.sh

# 执行部署
# root用户
bash deploy_caliper.sh
# 普通用户
sudo bash deploy_caliper.sh
```


## 执行流程说明
1. **系统环境检查**  
   → 识别 Ubuntu/CentOS 系统 → 验证权限 → 配置临时 sudo 免密  
2. **依赖安装**  
   → 安装系统基础依赖（区分 Ubuntu/CentOS 包管理）→ 配置 Docker 环境 → 安装 Docker Compose  
3. **镜像处理**  
   → 拉取官方镜像 → 失败则加载本地镜像 → 统一标签确保兼容性  
4. **Node 环境配置**  
   → 安装 NVM（支持双源）→ 安装 Node.js 8 → 配置 npm 国内镜像  
5. **Caliper 部署**  
   → 安装 Caliper CLI → 绑定 FISCO BCOS 适配器（带重试）→ 拉取测试案例  
6. **兼容性修复**  
   → 修改配置文件路径 → 修复事件发射器及 UUID 格式 → 补充密码学依赖  
7. **测试验证**  
   → 运行 HelloWorld 合约测试 → 输出部署结果及工作目录  


## 注意事项
- **网络要求**：联网环境需确保能访问 GitHub、Docker Hub（或配置镜像源）；离线环境需提前准备所有镜像和二进制文件。
- **权限说明**：Docker 安装后会添加当前用户到 docker 组，CentOS 7 可能需要执行 `newgrp docker` 刷新权限，或重新登录生效。
- **版本适配**：Node.js 固定为 8.x 版本（Caliper 0.2.0 强制依赖），请勿升级；Docker Compose 需使用与系统架构匹配的二进制文件。
- **目录说明**：部署成功后，工作目录位于脚本同级的 `caliper-workspace`，测试案例在 `caliper-benchmarks` 子目录。
- **错误处理**：若执行失败，可根据终端红色错误提示定位问题，常见原因包括：网络波动（重试即可）、文件路径错误（检查前置准备）、权限不足（用 root 执行）。
- **CentOS 7 特殊说明**：需确保系统已安装 `policycoreutils-python`（脚本已自动处理），关闭 SELinux 或配置相应规则避免容器启动失败。
