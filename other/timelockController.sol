// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (governance/TimelockController.sol)

pragma solidity ^0.8.20;

import { AccessControl } from "../access/AccessControl.sol";
import { ERC721Holder } from "../token/ERC721/utils/ERC721Holder.sol";
import { ERC1155Holder } from "../token/ERC1155/utils/ERC1155Holder.sol";
import { Address } from "../utils/Address.sol";

/**
 * @dev 合约模块，充当时间锁定控制器。当设置为 `Ownable` 智能合约的所有者时，
 * 它会在所有 `onlyOwner` 维护操作上强制执行时间锁定。这为受控合约的用户在
 * 可能存在风险的维护操作应用前退出提供了时间。
 *
 * 默认情况下，此合约是自管理的，这意味着管理任务必须经过时间锁定过程。
 * 提案者（proposer）角色负责提案，执行者（executor）角色负责执行操作。
 * 一个常见的用例是将 {TimelockController} 设为智能合约的所有者，并使用
 * 多重签名或DAO作为唯一的提案者。
 */
contract TimelockController is AccessControl, ERC721Holder, ERC1155Holder {
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
    uint256 internal constant _DONE_TIMESTAMP = uint256(1);

    mapping(bytes32 id => uint256) private _timestamps;
    uint256 private _minDelay;

    enum OperationState {
        Unset,
        Waiting,
        Ready,
        Done
    }

    /**
     * @dev 操作调用参数长度不匹配。
     */
    error TimelockInvalidOperationLength(
        uint256 targets,
        uint256 payloads,
        uint256 values
    );

    /**
     * @dev 调度操作不符合最小延迟要求。
     */
    error TimelockInsufficientDelay(uint256 delay, uint256 minDelay);

    /**
     * @dev 操作的当前状态不符合要求。
     * `expectedStates` 是一个位图，从右到左计数，为每个 OperationState 枚举位置启用位。
     *
     * 参见 {_encodeStateBitmap}.
     */
    error TimelockUnexpectedOperationState(
        bytes32 operationId,
        bytes32 expectedStates
    );

    /**
     * @dev 前置操作尚未完成。
     */
    error TimelockUnexecutedPredecessor(bytes32 predecessorId);

    /**
     * @dev 调用账户未授权。
     */
    error TimelockUnauthorizedCaller(address caller);

    /**
     * @dev 当调用被调度为操作 `id` 的一部分时触发。
     */
    event CallScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        uint256 delay
    );

    /**
     * @dev 当调用作为操作 `id` 的一部分执行时触发。
     */
    event CallExecuted(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data
    );

    /**
     * @dev 当新提案被调度且有非零 salt 时触发。
     */
    event CallSalt(bytes32 indexed id, bytes32 salt);

    /**
     * @dev 当操作 `id` 被取消时触发。
     */
    event Cancelled(bytes32 indexed id);

    /**
     * @dev 当未来操作的最小延迟时间被修改时触发。
     */
    event MinDelayChange(uint256 oldDuration, uint256 newDuration);

    /**
     * @dev 使用以下参数初始化合约：
     *
     * - `minDelay`: 操作的初始最小延迟时间（以秒为单位）
     * - `proposers`: 将被授予提案者和取消者角色的账户
     * - `executors`: 将被授予执行者角色的账户
     * - `admin`: 可选的被授予管理员角色的账户；使用零地址禁用
     *
     * 重要提示：可选的管理员可以在部署后协助角色的初始配置，而不受延迟限制，
     * 但此角色应随后被放弃，以通过时间锁定提案进行管理。以前版本的此合约会
     * 自动将此管理员角色分配给部署者，并且也应放弃此角色。
     */
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) {
        // 自我管理
        _grantRole(DEFAULT_ADMIN_ROLE, address(this));

        // 可选管理员
        if (admin != address(0)) {
            _grantRole(DEFAULT_ADMIN_ROLE, admin);
        }

        // 注册提案者和取消者
        for (uint256 i = 0; i < proposers.length; ++i) {
            _grantRole(PROPOSER_ROLE, proposers[i]);
            _grantRole(CANCELLER_ROLE, proposers[i]);
        }

        // 注册执行者
        for (uint256 i = 0; i < executors.length; ++i) {
            _grantRole(EXECUTOR_ROLE, executors[i]);
        }

        _minDelay = minDelay;
        emit MinDelayChange(0, minDelay);
    }

    /**
     * @dev 修饰符，使函数只能由某个角色调用。
     * 除了检查发送者的角色外，`address(0)` 的角色也会被考虑。
     * 将角色授予 `address(0)` 等同于为所有人启用此角色。
     */
    modifier onlyRoleOrOpenRole(bytes32 role) {
        if (!hasRole(role, address(0))) {
            _checkRole(role, _msgSender());
        }
        _;
    }

    /**
     * @dev 合约可能在维护过程中接收/持有ETH。
     */
    receive() external payable {}

    /**
     * @dev 参见 {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(AccessControl, ERC1155Holder)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev 返回id是否对应已注册的操作。
     * 包括等待中、已准备好和已完成的操作。
     */
    function isOperation(bytes32 id) public view returns (bool) {
        return getOperationState(id) != OperationState.Unset;
    }

    /**
     * @dev 返回操作是否待处理。注意，“待处理”操作也可能是“已准备好”的。
     */
    function isOperationPending(bytes32 id) public view returns (bool) {
        OperationState state = getOperationState(id);
        return state == OperationState.Waiting || state == OperationState.Ready;
    }

    /**
     * @dev 返回操作是否已准备好执行。注意，“已准备好”的操作也是“待处理”的。
     */
    function isOperationReady(bytes32 id) public view returns (bool) {
        return getOperationState(id) == OperationState.Ready;
    }

    /**
     * @dev 返回操作是否已完成。
     */
    function isOperationDone(bytes32 id) public view returns (bool) {
        return getOperationState(id) == OperationState.Done;
    }

    /**
     * @dev 返回操作变为准备好状态的时间戳（未设置的操作为0，已完成的操作为1）。
     */
    function getTimestamp(bytes32 id) public view virtual returns (uint256) {
        return _timestamps[id];
    }

    /**
     * @dev 返回操作状态。
     */
    function getOperationState(
        bytes32 id
    ) public view virtual returns (OperationState) {
        uint256 timestamp = getTimestamp(id);
        if (timestamp == 0) {
            return OperationState.Unset;
        } else if (timestamp == _DONE_TIMESTAMP) {
            return OperationState.Done;
        } else if (timestamp > block.timestamp) {
            return OperationState.Waiting;
        } else {
            return OperationState.Ready;
        }
    }

    /**
     * @dev 返回操作变为有效的最小延迟时间（以秒为单位）。
     *
     * 这个值可以通过执行调用 `updateDelay` 的操作来更改。
     */
    function getMinDelay() public view virtual returns (uint256) {
        return _minDelay;
    }

    /**
     * @dev 返回包含单笔交易的操作的标识符。
     */
    function hashOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) public pure virtual returns (bytes32) {
        return keccak256(abi.encode(target, value, data, predecessor, salt));
    }

    /**
     * @dev 返回包含一批交易的操作的标识符。
     */
    function hashOperationBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) public pure virtual returns (bytes32) {
        return
            keccak256(abi.encode(targets, values, payloads, predecessor, salt));
    }

    /**
     * @dev 调度包含单笔交易的操作。
     *
     * 如果 salt 非零，则触发 {CallSalt}，并触发 {CallScheduled}。
     *
     * 要求：
     *
     * - 调用者必须具有 'proposer' 角色。
     */
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual onlyRole(PROPOSER_ROLE) {
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        _schedule(id, delay);
        emit CallScheduled(id, 0, target, value, data, predecessor, delay);
        if (salt != bytes32(0)) {
            emit CallSalt(id, salt);
        }
    }

    /**
     * @dev 调度包含一批交易的操作。
     *
     * 如果 salt 非零，则触发 {CallSalt}，并为批处理中的每笔交易触发一个 {CallScheduled} 事件。
     *
     * 要求：
     *
     * - 调用者必须具有 'proposer' 角色。
     */
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual onlyRole(PROPOSER_ROLE) {
        if (
            targets.length != values.length || targets.length != payloads.length
        ) {
            revert TimelockInvalidOperationLength(
                targets.length,
                payloads.length,
                values.length
            );
        }

        bytes32 id = hashOperationBatch(
            targets,
            values,
            payloads,
            predecessor,
            salt
        );
        _schedule(id, delay);
        for (uint256 i = 0; i < targets.length; ++i) {
            emit CallScheduled(
                id,
                i,
                targets[i],
                values[i],
                payloads[i],
                predecessor,
                delay
            );
        }
        if (salt != bytes32(0)) {
            emit CallSalt(id, salt);
        }
    }

    /**
     * @dev 调度在给定延迟后生效的操作。
     */
    function _schedule(bytes32 id, uint256 delay) private {
        if (isOperation(id)) {
            revert TimelockUnexpectedOperationState(
                id,
                _encodeStateBitmap(OperationState.Unset)
            );
        }
        uint256 minDelay = getMinDelay();
        if (delay < minDelay) {
            revert TimelockInsufficientDelay(delay, minDelay);
        }
        _timestamps[id] = block.timestamp + delay;
    }

    /**
     * @dev 取消操作。
     *
     * 要求：
     *
     * - 调用者必须具有 'canceller' 角色。
     */
    function cancel(bytes32 id) public virtual onlyRole(CANCELLER_ROLE) {
        if (!isOperationPending(id)) {
            revert TimelockUnexpectedOperationState(
                id,
                _encodeStateBitmap(OperationState.Waiting) |
                    _encodeStateBitmap(OperationState.Ready)
            );
        }
        delete _timestamps[id];

        emit Cancelled(id);
    }

    /**
     * @dev 执行（已准备好）的单笔交易操作。
     *
     * 触发 {CallExecuted} 事件。
     *
     * 要求：
     *
     * - 调用者必须具有 'executor' 角色。
     */
    // 该函数可以重入，但不构成风险，因为 _afterCall 检查提案是否待处理，
    // 因此在重入期间对操作的任何修改都应被捕获。
    // slither-disable-next-line reentrancy-eth
    function execute(
        address target,
        uint256 value,
        bytes calldata payload,
        bytes32 predecessor,
        bytes32 salt
    ) public payable virtual onlyRoleOrOpenRole(EXECUTOR_ROLE) {
        bytes32 id = hashOperation(target, value, payload, predecessor, salt);

        _beforeCall(id, predecessor);
        _execute(target, value, payload);
        emit CallExecuted(id, 0, target, value, payload);
        _afterCall(id);
    }

    /**
     * @dev 执行（已准备好）的批量交易操作。
     *
     * 为批处理中的每笔交易触发一个 {CallExecuted} 事件。
     *
     * 要求：
     *
     * - 调用者必须具有 'executor' 角色。
     */
    // 该函数可以重入，但不构成风险，因为 _afterCall 检查提案是否待处理，
    // 因此在重入期间对操作的任何修改都应被捕获。
    // slither-disable-next-line reentrancy-eth
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) public payable virtual onlyRoleOrOpenRole(EXECUTOR_ROLE) {
        if (
            targets.length != values.length || targets.length != payloads.length
        ) {
            revert TimelockInvalidOperationLength(
                targets.length,
                payloads.length,
                values.length
            );
        }

        bytes32 id = hashOperationBatch(
            targets,
            values,
            payloads,
            predecessor,
            salt
        );

        _beforeCall(id, predecessor);
        for (uint256 i = 0; i < targets.length; ++i) {
            address target = targets[i];
            uint256 value = values[i];
            bytes calldata payload = payloads[i];
            _execute(target, value, payload);
            emit CallExecuted(id, i, target, value, payload);
        }
        _afterCall(id);
    }

    /**
     * @dev 执行操作的调用。
     */
    function _execute(
        address target,
        uint256 value,
        bytes calldata data
    ) internal virtual {
        (bool success, bytes memory returndata) = target.call{ value: value }(
            data
        );
        Address.verifyCallResult(success, returndata);
    }

    /**
     * @dev 执行操作调用前的检查。
     */
    function _beforeCall(bytes32 id, bytes32 predecessor) private view {
        if (!isOperationReady(id)) {
            revert TimelockUnexpectedOperationState(
                id,
                _encodeStateBitmap(OperationState.Ready)
            );
        }
        if (predecessor != bytes32(0) && !isOperationDone(predecessor)) {
            revert TimelockUnexecutedPredecessor(predecessor);
        }
    }

    /**
     * @dev 执行操作调用后的检查。
     */
    function _afterCall(bytes32 id) private {
        if (!isOperationReady(id)) {
            revert TimelockUnexpectedOperationState(
                id,
                _encodeStateBitmap(OperationState.Ready)
            );
        }
        _timestamps[id] = _DONE_TIMESTAMP;
    }

    /**
     * @dev 更改未来操作的最小时间锁定持续时间。
     *
     * 触发 {MinDelayChange} 事件。
     *
     * 要求：
     *
     * - 调用者必须是时间锁定本身。这只能通过调度并稍后执行一个操作来实现，
     * 其中时间锁定是目标，数据是对此函数的 ABI 编码调用。
     */
    function updateDelay(uint256 newDelay) external virtual {
        address sender = _msgSender();
        if (sender != address(this)) {
            revert TimelockUnauthorizedCaller(sender);
        }
        emit MinDelayChange(_minDelay, newDelay);
        _minDelay = newDelay;
    }

    /**
     * @dev 将 `OperationState` 编码为 `bytes32` 表示形式，其中每个位启用对应于
     * `OperationState` 枚举中的底层位置。例如：
     *
     * 0x000...1000
     *   ^^^^^^----- ...
     *         ^---- Done
     *          ^--- Ready
     *           ^-- Waiting
     *            ^- Unset
     */
    function _encodeStateBitmap(
        OperationState operationState
    ) internal pure returns (bytes32) {
        return bytes32(1 << uint8(operationState));
    }
}
