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
    const box = await ethers.getContract("Box");
    const boxAddress = await box.getAddress();
    console.log("111");
    // 编码函数调用数据
    const encodedFunctionCall = box.interface.encodeFunctionData(
        functionToCall,
        args,
    );
    console.log("222");
    const descriptionHash = ethers.keccak256(
        ethers.toUtf8Bytes(proposalDescription),
    );
    console.log("descriptionHash:", descriptionHash);
    console.log("333");

    const governor = await ethers.getContract("MyGovernor");
    const queueTx = await governor.queue(
        [boxAddress],
        [0],
        [encodedFunctionCall],
        descriptionHash,
    );
    console.log("444");

    await queueTx.wait(1);
    console.log("Proposal in queue..");

    if (developmentChains.includes(network.name)) {
        await moveTime(minDelay + 1);
        await moveBlocks(1);
    }
    console.log("555");

    console.log("Executing..");
    //execute
    const executeTx = await governor.execute(
        [boxAddress],
        [0],
        [encodedFunctionCall],
        descriptionHash,
    );
    console.log("666");

    await executeTx.wait(1);
    console.log("Executed..");
    console.log(`Box value is: ${await box.retrieve()}`);
}

queueAndExecute(FUNC, [FUNC_ARGS], DESCRIPTION)
    .then(() => process.exit(0))
    .catch((err) => {
        console.error(err);
        process.exit(1);
    });
