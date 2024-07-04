// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/ERC20Votes.sol)

pragma solidity ^0.8.20;

import { ERC20 } from "../ERC20.sol";
import { Votes } from "../../../governance/utils/Votes.sol";
import { Checkpoints } from "../../../utils/structs/Checkpoints.sol";

/**
 * @dev ERC20的扩展，支持类似Compound的投票和委托功能。此版本比Compound的更通用，
 * 支持的代币供应量高达2^208 - 1，而COMP限制在2^96 - 1。
 *
 * 注意：此合约不提供与Compound的COMP代币的接口兼容性。
 *
 * 此扩展维护了每个账户投票权的历史（检查点）。投票权可以通过直接调用{delegate}函数委托，
 * 或者通过提供签名使用{delegateBySig}。投票权可以通过公共访问器{getVotes}和{getPastVotes}查询。
 *
 * 默认情况下，代币余额不包括投票权。这使得转账更经济。缺点是它要求用户为了激活检查点并追踪其投票权而自我委托。
 */
abstract contract ERC20Votes is ERC20, Votes {
    /**
     * @dev 总供应量已超过限制，存在投票溢出的风险。
     */
    error ERC20ExceededSafeSupply(uint256 increasedSupply, uint256 cap);

    /**
     * @dev 最大代币供应量，默认为`type(uint208).max`（2^208 - 1）。
     *
     * 此最大值在{_update}中强制执行。它限制了代币的总供应量，否则为uint256，
     * 以便检查点可以存储在使用{{Votes}}的Trace208结构中。增加这个值不会
     * 去除潜在的限制，并将导致{_update}因{_transferVotingUnits}中的数学溢出而失败。
     * 如果需要额外的逻辑，可以使用覆盖来进一步限制总供应量（到更低的值）。
     * 在解决此函数的覆盖冲突时，应返回最小值。
     */
    function _maxSupply() internal view virtual returns (uint256) {
        return type(uint208).max;
    }

    /**
     * @dev 在代币转移时移动投票权。
     *
     * 触发一个{IVotes-DelegateVotesChanged}事件。
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override {
        super._update(from, to, value);
        if (from == address(0)) {
            uint256 supply = totalSupply();
            uint256 cap = _maxSupply();
            if (supply > cap) {
                revert ERC20ExceededSafeSupply(supply, cap);
            }
        }
        _transferVotingUnits(from, to, value);
    }

    /**
     * @dev 返回`account`的投票单位数。
     *
     * 警告：覆盖此函数可能会破坏内部投票会计。
     * `ERC20Votes`假设代币以1:1的比例映射到投票单位，这不容易改变。
     */
    function _getVotingUnits(
        address account
    ) internal view virtual override returns (uint256) {
        return balanceOf(account);
    }

    /**
     * @dev 获取`account`的检查点数量。
     */
    function numCheckpoints(
        address account
    ) public view virtual returns (uint32) {
        return _numCheckpoints(account);
    }

    /**
     * @dev 获取`account`的第`pos`个检查点。
     */
    function checkpoints(
        address account,
        uint32 pos
    ) public view virtual returns (Checkpoints.Checkpoint208 memory) {
        return _checkpoints(account, pos);
    }
}
