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
async function main() {
    console.log("Voting...");
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
            console.log("proposalId:", proposalId); // 输出: 73980182008898390335594542871076301189655466473211380186621331168932339587351
        } catch (err) {
            console.error("Error parsing JSON:", err);
        }
    });
    // 0 = Against, 1 = For, 2 = Abstain for this example
    const voteWay = 1;
    const reason = "I lika do da cha cha";
    await vote(proposalId, voteWay, reason);
}

async function vote(proposalId, voteWay, reason) {
    console.log("Voting...");
    const governor = await ethers.getContract("MyGovernor");
    const voteTx = await governor.castVoteWithReason(
        proposalId,
        voteWay,
        reason,
    );
    const voteTxReceipt = await voteTx.wait(1);
    console.log(voteTxReceipt.events[0].args.reason);
    const proposalState = await governor.state(proposalId);
    console.log(`Current Proposal State: ${proposalState}`);
    if (developmentChains.includes(network.name)) {
        await moveBlocks(VOTING_PERIOD + 1);
    }
}

// 执行投票函数并处理结果
main()
    .then(() => process.exit(0))
    .catch((err) => {
        console.error(err);
        process.exit(1);
    });
