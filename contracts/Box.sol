// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";

// 导入OpenZeppelin的Ownable合约，用于访问控制

/**
 * @dev Box合约继承自Ownable合约，实现了一个简单的存储和检索值的功能。
 * 这个合约提供了一个只允许合约所有者修改的值的存储空间。
 */
contract Box is Ownable {
    uint256 private value; // 定义一个私有状态变量value，用于存储数值
    event ValueChanged(uint256 newValue); // 定义一个事件，在值更新时触发

    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @dev 存储新值到value变量，并触发ValueChanged事件。
     * 只有合约的所有者可以调用此函数。
     */
    function store(uint256 newValue) public onlyOwner {
        value = newValue; // 设置value为传入的新值
        emit ValueChanged(newValue); // 触发ValueChanged事件，记录新值
    }

    /**
     * @dev 检索并返回当前最新存储的值。
     */
    function retrieve() public view returns (uint256) {
        return value; // 返回当前存储的值
    }
}
