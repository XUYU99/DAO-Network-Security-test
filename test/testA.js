// 修正后的 JavaScript 部署脚本代码
const { ethers, deployments, getNamedAccounts } = require("hardhat");

const setInformation = async () => {
    const { deploy, log } = deployments;
    // 获取命名账户中的部署者账户
    const { deployer } = await getNamedAccounts();

    // 使用 deploy 函数部署合约 A
    const Acontract = await deploy("A", {
        from: deployer, // 指定部署者账户地址
        log: true, // 记录部署日志
        args: [], // 合约构造函数参数，这里为空
        // waitConfirmations: 1, // 在非开发网络中用于确认的等待次数
    });

    log("Deployed 'A' contract");

    // 获取已部署的合约实例
    const deployedAcontract = await ethers.getContract("A", deployer);
    const conaddress = await deployedAcontract.getAddress();
    console.log(conaddress);

    // 调用 getName 方法
    const number = await deployedAcontract.getFavorNumber();
    console.log(number);
};

// 导出部署和设置信息函数
module.exports = setInformation;

// 设置函数的标签，用于脚本分类或过滤
setInformation.tags = ["setInformation"];
