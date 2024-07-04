// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/AccessControl.sol)

pragma solidity ^0.8.20;

import { IAccessControl } from "./IAccessControl.sol";
import { Context } from "../utils/Context.sol";
import { ERC165 } from "../utils/introspection/ERC165.sol";

/**
 * @dev 合约模块，允许子合约实现基于角色的访问控制机制。
 * 这是一个轻量级版本，不允许通过链上手段枚举角色成员，只能通过访问合约事件日志的链下手段进行枚举。
 * 有些应用程序可能需要链上枚举功能，对于这些情况，请参见 {AccessControlEnumerable}。
 *
 * 角色通过其 `bytes32` 标识符引用。应在外部 API 中公开并保持唯一。最好的实现方式是使用 `public constant` 哈希摘要：
 *
 * ```solidity
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * 角色可以用于表示一组权限。要限制对函数调用的访问，请使用 {hasRole}：
 *
 * ```solidity
 * function foo() public {
 *     require(hasRole(MY_ROLE, msg.sender));
 *     ...
 * }
 * ```
 *
 * 角色可以通过 {grantRole} 和 {revokeRole} 函数动态授予和撤销。每个角色都有一个关联的管理员角色，只有拥有该角色管理员角色的账户才能调用 {grantRole} 和 {revokeRole}。
 *
 * 默认情况下，所有角色的管理员角色是 `DEFAULT_ADMIN_ROLE`，这意味着只有拥有此角色的账户才能授予或撤销其他角色。可以使用 {_setRoleAdmin} 创建更复杂的角色关系。
 *
 * 警告：`DEFAULT_ADMIN_ROLE` 也是其自己的管理员：它有权限授予和撤销此角色。应采取额外的预防措施来保护被授予此角色的账户。我们建议使用 {AccessControlDefaultAdminRules} 来为此角色强制执行额外的安全措施。
 */
abstract contract AccessControl is Context, IAccessControl, ERC165 {
    struct RoleData {
        mapping(address account => bool) hasRole;
        bytes32 adminRole;
    }

    mapping(bytes32 role => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev 检查账户是否拥有特定角色的修饰符。如果 `_msgSender()` 没有 `role`，则抛出 {AccessControlUnauthorizedAccount} 错误并包括所需角色。
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
    }

    /**
     * @dev 参见 {IERC165-supportsInterface}。
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == type(IAccessControl).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev 返回 `true` 如果 `account` 被授予了 `role`。
     */
    function hasRole(
        bytes32 role,
        address account
    ) public view virtual returns (bool) {
        return _roles[role].hasRole[account];
    }

    /**
     * @dev 如果 `_msgSender()` 没有 `role`，则抛出 {AccessControlUnauthorizedAccount} 错误。重写此函数可以改变 {onlyRole} 修饰符的行为。
     */
    function _checkRole(bytes32 role) internal view virtual {
        _checkRole(role, _msgSender());
    }

    /**
     * @dev 如果 `account` 没有 `role`，则抛出 {AccessControlUnauthorizedAccount} 错误。
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!hasRole(role, account)) {
            revert AccessControlUnauthorizedAccount(account, role);
        }
    }

    /**
     * @dev 返回控制 `role` 的管理员角色。参见 {grantRole} 和 {revokeRole}。
     *
     * 要更改角色的管理员，请使用 {_setRoleAdmin}。
     */
    function getRoleAdmin(bytes32 role) public view virtual returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev 授予 `role` 给 `account`。
     *
     * 如果 `account` 尚未被授予 `role`，则触发 {RoleGranted} 事件。
     *
     * 要求：
     *
     * - 调用者必须拥有该 `role` 的管理员角色。
     *
     * 可能触发一个 {RoleGranted} 事件。
     */
    function grantRole(
        bytes32 role,
        address account
    ) public virtual onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    /**
     * @dev 撤销 `role` 从 `account`。
     *
     * 如果 `account` 被授予了 `role`，则触发 {RoleRevoked} 事件。
     *
     * 要求：
     *
     * - 调用者必须拥有该 `role` 的管理员角色。
     *
     * 可能触发一个 {RoleRevoked} 事件。
     */
    function revokeRole(
        bytes32 role,
        address account
    ) public virtual onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    /**
     * @dev 从调用账户撤销 `role`。
     *
     * 角色通常通过 {grantRole} 和 {revokeRole} 来管理：此函数的目的是为账户提供一种机制，以便在账户受到损害时（例如，当可信设备丢失时）失去其权限。
     *
     * 如果调用账户被撤销了 `role`，则触发 {RoleRevoked} 事件。
     *
     * 要求：
     *
     * - 调用者必须是 `callerConfirmation`。
     *
     * 可能触发一个 {RoleRevoked} 事件。
     */
    function renounceRole(
        bytes32 role,
        address callerConfirmation
    ) public virtual {
        if (callerConfirmation != _msgSender()) {
            revert AccessControlBadConfirmation();
        }

        _revokeRole(role, callerConfirmation);
    }

    /**
     * @dev 设置 `adminRole` 为 `role` 的管理员角色。
     *
     * 触发一个 {RoleAdminChanged} 事件。
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        bytes32 previousAdminRole = getRoleAdmin(role);
        _roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    /**
     * @dev 尝试授予 `role` 给 `account` 并返回一个布尔值，表示是否授予了 `role`。
     *
     * 内部函数，无访问限制。
     *
     * 可能触发一个 {RoleGranted} 事件。
     */
    function _grantRole(
        bytes32 role,
        address account
    ) internal virtual returns (bool) {
        if (!hasRole(role, account)) {
            _roles[role].hasRole[account] = true;
            emit RoleGranted(role, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev 尝试撤销 `role` 从 `account` 并返回一个布尔值，表示是否撤销了 `role`。
     *
     * 内部函数，无访问限制。
     *
     * 可能触发一个 {RoleRevoked} 事件。
     */
    function _revokeRole(
        bytes32 role,
        address account
    ) internal virtual returns (bool) {
        if (hasRole(role, account)) {
            _roles[role].hasRole[account] = false;
            emit RoleRevoked(role, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }
}
