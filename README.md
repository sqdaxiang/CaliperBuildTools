# Hyperledger Caliper 一键测试环境部署脚本

## 脚本概述
这是一个针对 FISCO BCOS 区块链平台的 Hyperledger Caliper 测试环境自动化部署脚本。通过全流程自动化操作，实现从系统环境检查、依赖安装到测试框架搭建及测试执行的完整部署，极大简化手动配置复杂度。

**适用系统**：仅在 Ubuntu 20.04 系统测试通过，其他系统版本可能存在兼容性问题。


## 核心功能
1. **环境校验**
   - 检查系统是否为 Ubuntu 发行版
   - 确保脚本以 root 或 sudo 权限运行
   - 验证工作目录及镜像存放目录有效性

2. **依赖管理**
   - 自动安装系统核心依赖（make、gcc、git、curl 等）
   - 配置 Docker 环境（使用阿里云源加速安装）
   - 离线安装 Docker Compose（需提前准备二进制文件）

3. **镜像管理**
   - 自动检查并拉取 FISCO BCOS 相关镜像
   - 拉取失败时自动加载本地镜像文件（支持离线环境）
   - 统一镜像标签确保兼容性

4. **Node.js 环境配置**
   - 安装 NVM（Node 版本管理器）并配置国内镜像
   - 安装 Node.js 8 及对应 npm 版本（Caliper 0.2.0 依赖）
   - 配置 npm 国内镜像加速依赖下载

5. **Caliper 部署**
   - 安装指定版本的 Caliper CLI（0.2.0）
   - 绑定 FISCO BCOS 适配器（支持自动修复安装失败问题）
   - 拉取测试案例仓库（支持 GitHub/Gitee 双源）

6. **兼容性修复**
   - 自动修改配置文件解决路径解析问题
   - 修复事件发射器空值及 UUID 格式兼容问题
   - 补充 secp256k1 密码学依赖库

7. **自动化测试**
   - 执行 HelloWorld 合约测试验证环境有效性
   - 输出详细部署结果及工作目录信息


## 使用方法

### 前置准备
1. 将脚本保存为 `deploy_caliper.sh`
2. 在脚本同级目录创建以下结构：
   ```
   ├── bin/
   │   └── docker-compose-Linux-x86_64  # Docker Compose 二进制文件
   └── images/
       ├── fiscobcos.tar                # FISCO BCOS 镜像（可选，离线用）
       └── solc-0.4.25.tar              # Solidity 编译器镜像（可选，离线用）
   ```

### 启动命令
```bash
# 赋予执行权限
chmod +x deploy_caliper.sh

# 执行部署（需联网，离线环境需确保镜像文件存在）
./deploy_caliper.sh
```


## 执行流程说明
1. 系统环境检查 → 确认 Ubuntu 系统及 root 权限
2. 安装系统依赖 → 配置 Docker 及 Docker Compose
3. 处理镜像文件 → 拉取或加载 FISCO BCOS 相关镜像
4. 配置 Node 环境 → 安装 NVM 及 Node.js 8
5. 部署 Caliper → 安装 CLI 并绑定 FISCO BCOS 适配器
6. 准备测试案例 → 拉取仓库并修复配置文件
7. 执行测试验证 → 运行 HelloWorld 合约测试
8. 输出部署结果 → 显示工作目录及成功信息


## 注意事项
- 脚本执行过程中需保持网络通畅（除非使用离线镜像）
- Docker 权限变更需重新登录生效，或执行 `newgrp docker` 临时生效
- 测试案例默认拉取自定义仓库，如需使用官方仓库可修改脚本中克隆地址
- 部署成功后，工作目录位于脚本同级的 `caliper-workspace`
- 若执行失败，可根据终端红色错误提示定位问题（通常为依赖缺失或文件路径错误）
