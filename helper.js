const { network } = require("hardhat");

/**
 * 将区块链状态前进指定数量的区块
 * @param {number} amount - 要前进的区块数量
 */
async function moveBlocks(amount) {
    for (let i = 0; i < amount; i++) {
        await network.provider.request({
            method: "evm_mine",
            params: [],
        });
    }
    console.log(`Moved ${amount} blocks`);
}

/**
 * 将区块链状态前进指定的时间（以秒为单位）
 * @param {number} amount - 要前进的时间，单位为秒
 */
async function moveTime(amount) {
    await network.provider.send("evm_increaseTime", [amount]);
    console.log(`Moved ${amount} seconds`);
}

module.exports = {
    moveBlocks,
    moveTime,
};
