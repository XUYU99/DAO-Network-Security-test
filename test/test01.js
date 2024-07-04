const { ethers, network, deployments } = require("hardhat");
const fs = require("fs");
const { moveBlocks } = require("../helper");
const {
    VOTING_DELAY,
    FUNC,
    FUNC_ARGS,
    DESCRIPTION,
    PROPOSAL_FILE,
    developmentChains,
} = require("../helper-hardhat-config");

async function test01() {
    const { deploy, log } = deployments;
    // 获取命名账户中的部署者账户
    const { deployer } = await getNamedAccounts();
    // 获取 GovernorContract 合约实例
    const governor = await ethers.getContract("MyGovernor");
    const governorAddress = await governor.getAddress();
    console.log("governorAddress：", governorAddress);

    const time = await governor.clock();
    console.log("time", Number(time));

    // const proposerVotes = await governor.getVotes(deployer, time);
    // console.log("proposerVotes", proposerVotes);
}

// 调用 makeProposal 函数并处理结果
test01()
    .then(() => process.exit(0))
    .catch((err) => {
        console.error(err);
        process.exit(1);
    });
