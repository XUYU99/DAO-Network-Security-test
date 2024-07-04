const networkConfig = {
    11155111: {
        name: "sepolia",
        ethUsdPriceFeed: "0x694AA1769357215DE4FAC081bf1f309aDC325306",
    },
    5: {
        name: "goerli",
        ethUsdPriceFeed: "0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e",
    },
};
// 定义了一个 developmentChains 数组，包含了开发中使用的链名称
const developmentChains = ["hardhat", "localhost"];
// 定义了一个 DECIMALS 常量，表示代币的小数位数
const DECIMALS = 9;
// 定义了一个 INITIAL_ANSWER 常量，表示初始数值
const INITIAL_ANSWER = 200000000000;

const minDelay = 3600;
const executors = [];
const proposers = [];

const VOTING_DELAY = 1; // blocks
const VOTING_PERIOD = 5; // blocks
const PROPOSAL_THRESHOLD = 0; // percentage
const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";
// Propose Script + Queue and Execute Script
const FUNC = "store";
const FUNC_ARGS = 100; // New value voted into Box.
const DESCRIPTION = "Proposal #1 - update  value of box to 100";
const PROPOSAL_FILE = "proposals.json";
const VOTE_REASON = "Don't ask,just I do";
module.exports = {
    networkConfig,
    developmentChains,
    DECIMALS,
    INITIAL_ANSWER,
    VOTING_DELAY,
    VOTING_PERIOD,
    PROPOSAL_THRESHOLD,
    minDelay,
    executors,
    proposers,
    ADDRESS_ZERO,
    FUNC,
    FUNC_ARGS,
    DESCRIPTION,
    PROPOSAL_FILE,
    VOTE_REASON,
};
