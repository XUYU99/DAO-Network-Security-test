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
    console.log("Voting...");
    // 从文件中读取提案ID
    // const proposals = JSON.parse(fs.readFileSync(PROPOSAL_FILE, "utf8"));
    // const value = proposals["31337"][0];
    // console.log("proposals:", value);
    // const proposalId = proposals[!network.config.chainId][0];
    // const plog = governor.interface.parseLog(proposeReceipt.logs[0]);
    // const proposalId = plog.args.proposalId;
    // 读取JSON文件的路径
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
            console.log("proposalId:", proposalId); // 输出: 73980182008898390335594542871076301189655466473211380186621331168932339587351
        } catch (err) {
            console.error("Error parsing JSON:", err);
        }
    });

    const governor = await ethers.getContract("MyGovernor");
    let initialState = await governor.state(proposalId);

    const voteWight = await governor.castVoteWithReason(
        proposalId,
        VOTE_YES,
        VOTE_REASON,
    );
    await voteWight.wait(1);

    let proposalState = await governor.state(proposalId);

    console.log("proposal State before voting is :", proposalState);
    if (developmentChains.includes(network.name)) {
        await moveBlocks(VOTING_PERIOD + 1);
    }
    proposalState = await governor.state(proposalId);
    console.log("proposal State after voting is :", proposalState);
}

// 执行投票函数并处理结果
vote()
    .then(() => process.exit(0))
    .catch((err) => {
        console.error(err);
        process.exit(1);
    });
