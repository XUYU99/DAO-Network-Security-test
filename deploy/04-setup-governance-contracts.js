const { ethers, deployments, getNamedAccounts } = require("hardhat");
const { ADDRESS_ZERO } = require("../helper-hardhat-config");

const setupGovernanceContract = async () => {
    const { deploy, log, get } = deployments;
    const { deployer } = await getNamedAccounts();
    log("Deploying the  04-setup-governance-contracts ~~");
    const governanceToken = await ethers.getContract(
        "GovernanceToken",
        deployer,
    );
    const timeLock = await ethers.getContract("TimeLock", deployer);
    const timeLockaddress = await timeLock.getAddress();
    const governor = await ethers.getContract("MyGovernor", deployer);
    const governoraddress = await governor.getAddress();
    log("governoraddress: ", governoraddress);
    log("Setting up roles...");
    const proposerRole = await timeLock.PROPOSER_ROLE();
    const executorRole = await timeLock.EXECUTOR_ROLE();
    const cancellerRole = await timeLock.CANCELLER_ROLE();

    const proposerTx = await timeLock.grantRole(proposerRole, governoraddress);
    // console.log("proposerTx: ", proposerTx);
    await proposerTx.wait(1);
    const executorTx = await timeLock.grantRole(executorRole, ADDRESS_ZERO);
    await executorTx.wait(1);
    const revokeTx = await timeLock.revokeRole(cancellerRole, deployer);
    await revokeTx.wait(1);
    log("04-Roles setup OK. Deployer is no longer the admin for 'TimeLock'.");
    log("---------------");
};
module.exports = setupGovernanceContract;
setupGovernanceContract.tags = ["all", "setupGovernanceContract"];
