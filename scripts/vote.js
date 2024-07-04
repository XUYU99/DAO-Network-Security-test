const { ethers, network, deployments } = require("hardhat");
const fs = require("fs");
const { moveBlocks } = require("../helper");
const {
    PROPOSAL_FILE,
    VOTE_REASON,
    VOTING_PERIOD,
    developmentChains,
} = require("../helper-hardhat-config");

const index = 0;
const VOTE_NO = 0;
const VOTE_YES = 1;
const VOTE_ABSTAIN = 2; //弃权

// uint256 proposalId,
// uint8 support,
// string memory reason
/**
 * 执行投票
 */
async function vote() {
    console.log("开始投票");
    const { deployer } = await getNamedAccounts();
    // 读取JSON文件的路径
    // 从文件中读取提案ID
    const filePath = "./proposals.json";
    let proposalId;
    fs.readFile(filePath, "utf8", (err, fileContents) => {
        if (err) {
            console.error("Error reading the file:", err);
            return;
        }
        try {
            // 解析JSON字符串
            const data = JSON.parse(fileContents);
            proposalId = data[network.config.chainId][0];
            console.log("proposalId: ", proposalId); // 输出: 73980182008898390335594542871076301189655466473211380186621331168932339587351
        } catch (err) {
            console.error("Error parsing JSON:", err);
        }
    });
    console.log("投票者地址为：", deployer);

    const governor = await ethers.getContract("MyGovernor");
    let initproposalState = await governor.state(proposalId);
    let initproposalState1 = printProposalState(Number(initproposalState));
    console.log("投票前提案的状态为 :", initproposalState1);
    console.log("投票ing...");
    const voteWight = await governor.castVoteWithReason(
        proposalId,
        VOTE_YES,
        VOTE_REASON,
    );
    await voteWight.wait(1);

    //加快区块速度
    if (developmentChains.includes(network.name)) {
        await moveBlocks(VOTING_PERIOD + 1);
    }
    let proposalState = await governor.state(proposalId);
    let proposalState1 = printProposalState(Number(proposalState));
    console.log("投票完成后提案的状态为 :", proposalState1);
    // 根据提案状态输出相应的信息
}

async function printProposalState(proposalState) {
    let state;
    switch (proposalState) {
        case 1:
            state = `Active`;
            return state;
        case 4:
            state = `Succeeded`;
            return state;

        default:
            console.log(`未知状态`);
    }
}

// 执行投票函数并处理结果
vote()
    .then(() => process.exit(0))
    .catch((err) => {
        console.error(err);
        process.exit(1);
    });
