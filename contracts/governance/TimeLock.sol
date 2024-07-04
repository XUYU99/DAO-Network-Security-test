// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/governance/TimelockController.sol";

contract TimeLock is TimelockController {
    /**
     * @dev 使用以下参数初始化合约：
     * - `minDelay`: 操作的初始最小延迟时间（以秒为单位）
     * - `proposers`: 将被授予提案者和取消者角色的账户
     * - `executors`: 将被授予执行者角色的账户
     * - `admin`: 可选的被授予管理员角色的账户；使用零地址禁用
     * 角色有这些：
     * ytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
     * bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
     * bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
     * uint256 internal constant _DONE_TIMESTAMP = uint256(1);
     */
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
