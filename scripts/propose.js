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
/**
 * 创建提案
 * @param {string} functionToCall - 要调用的函数名称
 * @param {number[]} args - 函数参数数组
 * @param {string} proposalDescription - 提案描述
 */

async function makeProposal(functionToCall, args, proposalDescription) {
    const { deploy, log, get } = deployments;
    // 获取 GovernorContract 合约实例
    const governor = await ethers.getContract("MyGovernor");
    // const governorAddress = await governor.getAddress();
    // console.log("governorAddress：", governorAddress);
    // 获取 Box 合约实例
    const box = await ethers.getContract("Box");
    const boxAddress = await box.getAddress();
    // 编码函数调用数据
    const encodedFunctionCall = box.interface.encodeFunctionData(
        functionToCall,
        args,
    );

    // 打印调试信息
    console.log("Function to call: ", functionToCall);
    console.log("Args: ", args);
    console.log("Encoded Function Call: ", encodedFunctionCall);
    console.log("Proposal Description: ", proposalDescription);

    // 创建提案
    const proposeTx = await governor.propose(
        [boxAddress], // 提案目标合约地址数组
        [0], // 提案价值数组（这里为0）
        [encodedFunctionCall], // 提案函数调用数据数组
        proposalDescription, // 提案描述
    );
    console.log("1");
    // 等待提案交易确认
    const proposeReceipt = await proposeTx.wait(1);
    // console.log("2 proposeReceipt:", proposeReceipt);
    // 如果在开发链上，加速时间以便进行投票
    if (developmentChains.includes(network.name)) {
        await moveBlocks(VOTING_DELAY + 1);
    }
    console.log("3");
    // 获取提案ID
    //const proposalId = proposeReceipt.events[0].args.proposalId;
    const plog = governor.interface.parseLog(proposeReceipt.logs[0]);
    const proposalId = plog.args.proposalId;
    console.log("proposalId is ", proposalId.toString());
    // 保存提案ID到文件
    fs.writeFileSync(
        PROPOSAL_FILE,
        JSON.stringify({
            [network.config.chainId.toString()]: [proposalId.toString()],
        }),
    );

    // 获取提案状态
    const proposalState = await governor.state(proposalId);
    // 提案状态：1 表示未通过，0 表示通过
    console.log(`Current Proposal State: ${proposalState}`);
}

// 调用 makeProposal 函数并处理结果
makeProposal(FUNC, [FUNC_ARGS], DESCRIPTION)
    .then(() => process.exit(0))
    .catch((err) => {
        console.error(err);
        process.exit(1);
    });
