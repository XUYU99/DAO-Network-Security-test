const { ethers, deployments, getNamedAccounts } = require("hardhat");

// 部署治理代币的异步函数
const timeLock = async () => {
    // 从 hardhat 部署工具中获取 deploy 和 log 函数
    const { deploy, log } = deployments;
    // 获取命名账户中的部署者账户
    const { deployer } = await getNamedAccounts();
    log("Deploying the  02-deploy-timelock ~~");
    const minDelay = 3600;
    const proposers = [];
    const executors = [];
    const admin = deployer;
    // 使用 deploy 函数部署时间锁合约
    const timeLockContract = await deploy("TimeLock", {
        from: deployer, // 指定部署者账户地址
        log: true, // 记录部署日志
        args: [minDelay, proposers, executors, admin], // 合约构造函数参数，这里为空
        // waitConfirmations: 1, // 在非开发网络中用于确认的等待次数]
    });
    log(`02-timelock contract deployed at ${timeLockContract.address}`);
    log("---------------");
};
// 导出部署治理代币函数
module.exports = timeLock;
// 设置部署治理代币函数的标签，用于脚本分类或过滤
timeLock.tags = ["all", "timelock"];
