const { ethers, deployments, getNamedAccounts } = require("hardhat");

const deployBox = async () => {
    const { deploy, log, get } = deployments;
    const { deployer } = await getNamedAccounts();
    log("Deploying 'Box' Contract....");

    const box = await deploy("Box", {
        from: deployer,
        args: [deployer],
        log: true,
        waitConfirmations: 1,
    });

    log(`05-Deployed 'Box' at ${box.address}`);

    const boxContract = await ethers.getContractAt("Box", box.address);
    const timelockContract = await ethers.getContract("TimeLock", deployer);
    const timelockAddress = await timelockContract.getAddress();
    const transferTx = await boxContract.transferOwnership(timelockAddress);
    await transferTx.wait(1);
    log("Ownership of 'Box' transferred to 'TimeLock'...");
    log("---------------");
    const governor = await ethers.getContract("MyGovernor");
    const governoraddress = await governor.getAddress();
    log("governoraddress: ", governoraddress);
};
module.exports = deployBox;
deployBox.tags = ["all", "box"];
