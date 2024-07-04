// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.20;

import { IERC20 } from "./IERC20.sol";
import { IERC20Metadata } from "./extensions/IERC20Metadata.sol";
import { Context } from "../../utils/Context.sol";
import { IERC20Errors } from "../../interfaces/draft-IERC6093.sol";

/**
 * @dev {IERC20} 接口的实现。
 *
 * 这个实现对代币的创建方式是无关的。这意味着必须在派生合约中使用 {_mint} 添加供应机制。
 *
 * 提示：有关详细的写作，请参阅我们的指南
 * https://forum.openzeppelin.com/t/how-to-implement-erc20-supply-mechanisms/226[如何
 * 实现供应机制]。
 *
 * {decimals} 的默认值为 18。要更改此值，应重写此函数以返回不同的值。
 *
 * 我们遵循了 OpenZeppelin 合约的通用准则：函数在失败时返回 `false` 而不是重置。这种行为
 * 是惯用的，并且不与 ERC20 应用程序的期望冲突。
 *
 * 此外，调用 {transferFrom} 时会触发 {Approval} 事件。
 * 这允许应用程序仅通过监听这些事件来重建所有账户的允许值。EIP 的其他实现可能不会发出
 * 这些事件，因为规范并不要求这样做。
 */
abstract contract ERC20 is Context, IERC20, IERC20Metadata, IERC20Errors {
    mapping(address account => uint256) private _balances; // 账户余额映射

    mapping(address account => mapping(address spender => uint256))
        private _allowances; // 允许值映射

    uint256 private _totalSupply; // 总供应量

    string private _name; // 代币名称
    string private _symbol; // 代币符号

    /**
     * @dev 设置 {name} 和 {symbol} 的值。
     *
     * 这两个值都是不可变的：它们只能在构造函数中设置一次。
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev 返回代币的名称。
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev 返回代币的符号，通常是名称的简短版本。
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev 返回用于获取用户表示的十进制位数。
     * 例如，如果 `decimals` 等于 `2`，则 `505` 代币的余额应显示为 `5.05` (`505 / 10 ** 2`)。
     *
     * 代币通常选择 18 的值，模仿以太坊和 Wei 之间的关系。这是此函数返回的默认值，除非
     * 被重写。
     *
     * 注意：此信息仅用于 _显示_ 目的：它不会以任何方式影响合约的任何算术运算，包括
     * {IERC20-balanceOf} 和 {IERC20-transfer}。
     */
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /**
     * @dev 参见 {IERC20-totalSupply}。
     */
    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev 参见 {IERC20-balanceOf}。
     */
    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev 参见 {IERC20-transfer}。
     *
     * 要求：
     *
     * - `to` 不能是零地址。
     * - 调用者必须至少有 `value` 的余额。
     */
    function transfer(address to, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    /**
     * @dev 参见 {IERC20-allowance}。
     */
    function allowance(
        address owner,
        address spender
    ) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev 参见 {IERC20-approve}。
     *
     * 注意：如果 `value` 是最大值 `uint256`，则在 `transferFrom` 时不会更新允许值。
     * 这在语义上相当于无限批准。
     *
     * 要求：
     *
     * - `spender` 不能是零地址。
     */
    function approve(
        address spender,
        uint256 value
    ) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    /**
     * @dev 参见 {IERC20-transferFrom}。
     *
     * 触发一个 {Approval} 事件，指示更新的允许值。这不是 EIP 要求的。
     * 参见 {ERC20} 开头的注释。
     *
     * 注意：如果当前允许值是最大 `uint256`，则不会更新允许值。
     *
     * 要求：
     *
     * - `from` 和 `to` 不能是零地址。
     * - `from` 必须至少有 `value` 的余额。
     * - 调用者必须至少有 `from` 代币的 `value` 的允许值。
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    /**
     * @dev 将 `value` 数量的代币从 `from` 转移到 `to`。
     *
     * 此内部函数等同于 {transfer}，可用于例如实现自动代币费用、削减机制等。
     *
     * 触发一个 {Transfer} 事件。
     *
     * 注意：此函数不是虚拟的，应该重写 {_update}。
     */
    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value);
    }

    /**
     * @dev 将 `value` 数量的代币从 `from` 转移到 `to`，或者如果 `from`（或 `to`）是零地址，则替代铸造（或销毁）。
     * 所有转账、铸造和销毁的自定义都应通过重写此函数完成。
     *
     * 触发一个 {Transfer} 事件。
     */
    function _update(address from, address to, uint256 value) internal virtual {
        if (from == address(0)) {
            // 溢出检查：其余代码假设 totalSupply 永远不会溢出
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // 不可能溢出：value <= fromBalance <= totalSupply。
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                // 不可能溢出：value <= totalSupply 或 value <= fromBalance <= totalSupply。
                _totalSupply -= value;
            }
        } else {
            unchecked {
                // 不可能溢出：balance + value 最多为 totalSupply，我们知道它适合 uint256。
                _balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    /**
     * @dev 创建 `value` 数量的代币并分配给 `account`，通过从 address(0) 转移。
     * 依赖于 `_update` 机制。
     *
     * 触发一个 {Transfer} 事件，将 `from` 设置为零地址。
     *
     * 注意：此函数不是虚拟的，应重写 {_update}。
     */
    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, value);
    }

    /**
     * @dev 从 `account` 销毁 `value` 数量的代币，降低总供应量。
     * 依赖于 `_update` 机制。
     *
     * 触发一个 {Transfer} 事件，将 `to` 设置为零地址。
     *
     * 注意：此函数不是虚拟的，应重写 {_update}。
     */
    function _burn(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        _update(account, address(0), value);
    }

    /**
     * @dev 将 `owner` 对 `spender` 的代币允许值设置为 `value`。
     *
     * 此内部函数等同于 `approve`，可用于例如设置某些子系统的自动允许值等。
     *
     * 触发一个 {Approval} 事件。
     *
     * 要求：
     *
     * - `owner` 不能是零地址。
     * - `spender` 不能是零地址。
     *
     * 对此逻辑的重写应针对具有附加 `bool emitEvent` 参数的变体。
     */
    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    /**
     * @dev {_approve} 的变体，带有启用或禁用 {Approval} 事件的可选标志。
     *
     * 默认情况下（调用 {_approve} 时），标志设置为 true。另一方面，
     * `transferFrom` 操作期间由 `_spendAllowance` 进行的批准更改将标志设置为 false。
     * 这通过在 `transferFrom` 操作期间不发出任何 `Approval` 事件来节省 gas。
     *
     * 任何希望在 `transferFrom` 操作期间继续发出 `Approval` 事件的人可以使用以下重写将标志强制为 true：
     * ```
     * function _approve(address owner, address spender, uint256 value, bool) internal virtual override {
     *     super._approve(owner, spender, value, true);
     * }
     * ```
     *
     * 要求与 {_approve} 相同。
     */
    function _approve(
        address owner,
        address spender,
        uint256 value,
        bool emitEvent
    ) internal virtual {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    /**
     * @dev 根据消耗的 `value` 更新 `owner` 对 `spender` 的允许值。
     *
     * 如果允许值是无限的，则不会更新允许值。
     * 如果没有足够的允许值可用，则会恢复。
     *
     * 不触发 {Approval} 事件。
     */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 value
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(
                    spender,
                    currentAllowance,
                    value
                );
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}
