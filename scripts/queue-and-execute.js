const { ethers, network, deployments } = require("hardhat");
const fs = require("fs");
const { moveBlocks, moveTime } = require("../helper");
const {
    FUNC,
    FUNC_ARGS,
    DESCRIPTION,
    developmentChains,
    minDelay,
} = require("../helper-hardhat-config");

async function queueAndExecute(functionToCall, args, proposalDescription) {
    console.log("投票结束，开始执行提案");
    const box = await ethers.getContract("Box");
    const boxAddress = await box.getAddress();
    console.log(`执行前 Box value is: ${await box.retrieve()}`);
    // 编码函数调用数据
    const encodedFunctionCall = box.interface.encodeFunctionData(
        functionToCall,
        args,
    );

    const descriptionHash = ethers.keccak256(
        ethers.toUtf8Bytes(proposalDescription),
    );

    const governor = await ethers.getContract("MyGovernor");
    const queueTx = await governor.queue(
        [boxAddress],
        [0],
        [encodedFunctionCall],
        descriptionHash,
    );

    await queueTx.wait(1);
    console.log("提案在队列中....");

    if (developmentChains.includes(network.name)) {
        await moveTime(minDelay + 1);
        await moveBlocks(1);
    }

    console.log("提案执行ing...");
    //execute
    const executeTx = await governor.execute(
        [boxAddress],
        [0],
        [encodedFunctionCall],
        descriptionHash,
    );

    await executeTx.wait(1);
    console.log("提案执行完毕...");
    console.log(`执行后 Box value is: ${await box.retrieve()}`);
}

queueAndExecute(FUNC, [FUNC_ARGS], DESCRIPTION)
    .then(() => process.exit(0))
    .catch((err) => {
        console.error(err);
        process.exit(1);
    });
