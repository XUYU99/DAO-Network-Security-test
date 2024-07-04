const { ethers, deployments, getNamedAccounts } = require("hardhat");

// 部署治理代币的异步函数
const deployGovernanceToken = async () => {
    // 从 hardhat 部署工具中获取 deploy 和 log 函数
    const { deploy, log } = deployments;
    // 获取命名账户中的部署者账户
    const { deployer } = await getNamedAccounts();

    // 记录日志，显示开始部署治理代币，并显示部署者账户地址
    log("hello, start to 01-deploy ~~", "deployer is :", deployer);

    // 使用 deploy 函数部署治理代币合约
    const governanceToken = await deploy("GovernanceToken", {
        from: deployer, // 指定部署者账户地址
        log: true, // 记录部署日志
        args: [], // 合约构造函数参数，这里为空
        // waitConfirmations: 1, // 在非开发网络中用于确认的等待次数
    });

    // 记录日志，显示部署成功并显示治理代币合约地址
    log("01-Deployed 'GovernanceToken' at", governanceToken.address);

    // 将投票权委托给部署者
    await delegate(governanceToken.address, deployer);
    // 记录日志，显示投票权已委托给部署者
    log(`01-Delegated`);
    console.log("---------------");
};

// 导出部署治理代币函数
module.exports = deployGovernanceToken;
// 设置部署治理代币函数的标签，用于脚本分类或过滤
deployGovernanceToken.tags = ["GovernanceToken"];

// 委托投票权的异步函数
const delegate = async (governanceTokenAddress, delegatedAccount) => {
    // 获取已部署的治理代币合约实例
    const governanceToken = await ethers.getContractAt(
        "GovernanceToken", // 合约名称
        governanceTokenAddress, // 合约地址
    );

    // 调用合约的 delegate 函数，将投票权委托给指定账户
    const txResponse = await governanceToken.delegate(delegatedAccount);
    // 等待交易确认
    await txResponse.wait(1);

    // 打印日志，显示委托账户的检查点数量
    console.log(
        `Checkpoints: ${await governanceToken.numCheckpoints(delegatedAccount)}`,
    );
};
