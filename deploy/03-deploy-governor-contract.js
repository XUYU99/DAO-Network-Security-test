const { ethers, deployments, getNamedAccounts } = require("hardhat");
const {
    VOTING_DELAY,
    VOTING_PERIOD,
    PROPOSAL_THRESHOLD,
} = require("../helper-hardhat-config");
// 部署治理代币的异步函数
const deployGovernorContract = async () => {
    // 从 hardhat 部署工具中获取 deploy 和 log 函数
    const { deploy, log, get } = deployments;
    // 获取命名账户中的部署者账户
    const { deployer } = await getNamedAccounts();
    log("Deploying the  03-deploy-governor-contract ~~");
    const governanceToken = await get("GovernanceToken");
    const timeLock = await get("TimeLock");
    const governorContract = await deploy("MyGovernor", {
        from: deployer,
        args: [
            governanceToken.address,
            timeLock.address,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
        ],
        log: true,
        waitConfirmations: 1, // optional
    });
    log(`03-Deployed 'GovernorContract' at ${governorContract.address} `);
    log("---------------");
};

module.exports = deployGovernorContract;
deployGovernorContract.tags = ["all", "deployGovernorContract"];
