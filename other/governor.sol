// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (governance/Governor.sol)

pragma solidity ^0.8.20;

import { IERC721Receiver } from "../token/ERC721/IERC721Receiver.sol";
import { IERC1155Receiver } from "../token/ERC1155/IERC1155Receiver.sol";
import { EIP712 } from "../utils/cryptography/EIP712.sol";
import { SignatureChecker } from "../utils/cryptography/SignatureChecker.sol";
import { IERC165, ERC165 } from "../utils/introspection/ERC165.sol";
import { SafeCast } from "../utils/math/SafeCast.sol";
import { DoubleEndedQueue } from "../utils/structs/DoubleEndedQueue.sol";
import { Address } from "../utils/Address.sol";
import { Context } from "../utils/Context.sol";
import { Nonces } from "../utils/Nonces.sol";
import { IGovernor, IERC6372 } from "./IGovernor.sol";

/**
 * @dev 治理系统的核心，设计用于通过各种模块进行扩展。
 *
 * 该合约是抽象的，需要在各种模块中实现多个函数：
 *
 * - 计数模块必须实现 {quorum}, {_quorumReached}, {_voteSucceeded} 和 {_countVote}
 * - 投票模块必须实现 {_getVotes}
 * - 此外，还必须实现 {votingPeriod}
 */
abstract contract Governor is
    Context,
    ERC165,
    EIP712,
    Nonces,
    IGovernor,
    IERC721Receiver,
    IERC1155Receiver
{
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    bytes32 public constant BALLOT_TYPEHASH =
        keccak256(
            "Ballot(uint256 proposalId,uint8 support,address voter,uint256 nonce)"
        );
    bytes32 public constant EXTENDED_BALLOT_TYPEHASH =
        keccak256(
            "ExtendedBallot(uint256 proposalId,uint8 support,address voter,uint256 nonce,string reason,bytes params)"
        );

    struct ProposalCore {
        address proposer;
        uint48 voteStart;
        uint32 voteDuration;
        bool executed;
        bool canceled;
        uint48 etaSeconds;
    }

    bytes32 private constant ALL_PROPOSAL_STATES_BITMAP =
        bytes32((2 ** (uint8(type(ProposalState).max) + 1)) - 1);
    string private _name;

    mapping(uint256 proposalId => ProposalCore) private _proposals;

    // 此队列跟踪操作自己的治理者。受 {onlyGovernance} 修饰符保护的函数调用需要在此队列中被列入白名单。
    // 白名单设置在 {execute} 中，由 {onlyGovernance} 修饰符消耗，最终在 {_executeOperations} 完成后重置。
    // 这确保了 {onlyGovernance} 保护的调用只能通过成功的提案来实现。
    DoubleEndedQueue.Bytes32Deque private _governanceCall;

    /**
     * @dev 限制一个函数只能通过治理提案执行。例如，{GovernorSettings} 中的治理参数设置器使用此修饰符进行保护。
     *
     * 执行地址可能与治理者自己的地址不同，例如它可能是一个时间锁。这可以通过模块通过覆盖 {_executor} 进行定制。
     * 执行者只能在治理者的 {execute} 函数执行期间调用这些函数，在其他任何情况下都不能调用。
     * 因此，例如，附加的时间锁提案者不能在不通过治理协议的情况下更改治理参数（自 v4.6 起）。
     */
    modifier onlyGovernance() {
        _checkGovernance();
        _;
    }

    /**
     * @dev 设置 {name} 和 {version} 的值
     */
    constructor(string memory name_) EIP712(name_, version()) {
        _name = name_;
    }

    /**
     * @dev 用于接收将由治理者处理的ETH的函数（如果执行者是第三方合约，则禁用）
     */
    receive() external payable virtual {
        if (_executor() != address(this)) {
            revert GovernorDisabledDeposit();
        }
    }

    /**
     * @dev 查看 {IERC165-supportsInterface}。
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165, ERC165) returns (bool) {
        return
            interfaceId == type(IGovernor).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev 查看 {IGovernor-name}。
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev 查看 {IGovernor-version}。
     */
    function version() public view virtual returns (string memory) {
        return "1";
    }

    /**
     * @dev 查看 {IGovernor-hashProposal}。
     *
     * 提案 ID 通过哈希 ABI 编码的 `targets` 数组、`values` 数组、`calldatas` 数组和 descriptionHash（bytes32 本身是描述字符串的 keccak256 哈希）生成。
     * 可以从 {ProposalCreated} 事件中的提案数据生成此提案 ID。甚至可以在提案提交之前提前计算出来。
     *
     * 注意，chainId 和治理者地址不是提案 ID 计算的一部分。因此，如果在多个治理者中跨多个网络提交相同的提案（具有相同的操作和相同的描述），
     * 则会生成相同的 ID。这也意味着，为了在同一个治理者上执行相同的操作两次，提案者必须更改描述以避免提案 ID 冲突。
     */
    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure virtual returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encode(targets, values, calldatas, descriptionHash)
                )
            );
    }

    /**
     * @dev 查看 {IGovernor-state}。
     */
    function state(
        uint256 proposalId
    ) public view virtual returns (ProposalState) {
        // 我们将结构字段一次性读入堆栈，以便 Solidity 发出单个 SLOAD
        ProposalCore storage proposal = _proposals[proposalId];
        bool proposalExecuted = proposal.executed;
        bool proposalCanceled = proposal.canceled;

        if (proposalExecuted) {
            return ProposalState.Executed;
        }

        if (proposalCanceled) {
            return ProposalState.Canceled;
        }

        uint256 snapshot = proposalSnapshot(proposalId);

        if (snapshot == 0) {
            revert GovernorNonexistentProposal(proposalId);
        }

        uint256 currentTimepoint = clock();

        if (snapshot >= currentTimepoint) {
            return ProposalState.Pending;
        }

        uint256 deadline = proposalDeadline(proposalId);

        if (deadline >= currentTimepoint) {
            return ProposalState.Active;
        } else if (!_quorumReached(proposalId) || !_voteSucceeded(proposalId)) {
            return ProposalState.Defeated;
        } else if (proposalEta(proposalId) == 0) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Queued;
        }
    }

    /**
     * @dev 查看 {IGovernor-proposalThreshold}。
     */
    function proposalThreshold() public view virtual returns (uint256) {
        return 0;
    }

    /**
     * @dev 查看 {IGovernor-proposalSnapshot}。
     */
    function proposalSnapshot(
        uint256 proposalId
    ) public view virtual returns (uint256) {
        return _proposals[proposalId].voteStart;
    }

    /**
     * @dev 查看 {IGovernor-proposalDeadline}。
     */
    function proposalDeadline(
        uint256 proposalId
    ) public view virtual returns (uint256) {
        return
            _proposals[proposalId].voteStart +
            _proposals[proposalId].voteDuration;
    }

    /**
     * @dev 查看 {IGovernor-proposalProposer}。
     */
    function proposalProposer(
        uint256 proposalId
    ) public view virtual returns (address) {
        return _proposals[proposalId].proposer;
    }

    /**
     * @dev 查看 {IGovernor-proposalEta}。
     */
    function proposalEta(
        uint256 proposalId
    ) public view virtual returns (uint256) {
        return _proposals[proposalId].etaSeconds;
    }

    /**
     * @dev 查看 {IGovernor-proposalNeedsQueuing}。
     */
    function proposalNeedsQueuing(uint256) public view virtual returns (bool) {
        return false;
    }

    /**
     * @dev 如果 `msg.sender` 不是执行者则还原。
     * 如果执行者不是合约本身，则如果 `msg.data` 未被列入 {execute} 操作的白名单，则该函数会还原。参见 {onlyGovernance}。
     */
    function _checkGovernance() internal virtual {
        if (_executor() != _msgSender()) {
            revert GovernorOnlyExecutor(_msgSender());
        }
        if (_executor() != address(this)) {
            bytes32 msgDataHash = keccak256(_msgData());
            // 循环直到弹出预期的操作 - 如果双端队列为空（操作未被授权），则抛出异常
            while (_governanceCall.popFront() != msgDataHash) {}
        }
    }

    /**
     * @dev 已投票

的票数已超过阈值。
     */
    function _quorumReached(
        uint256 proposalId
    ) internal view virtual returns (bool);

    /**
     * @dev 提案是否成功。
     */
    function _voteSucceeded(
        uint256 proposalId
    ) internal view virtual returns (bool);

    /**
     * @dev 获取在特定 `timepoint` 上 `account` 的投票权重，用于描述 `params` 的投票。
     */
    function _getVotes(
        address account,
        uint256 timepoint,
        bytes memory params
    ) internal view virtual returns (uint256);

    /**
     * @dev 为 `proposalId` 由 `account` 注册投票，支持 `support`，投票权重 `weight` 和投票参数 `params`。
     *
     * 注意：支持是通用的，具体含义取决于使用的投票系统。
     */
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight,
        bytes memory params
    ) internal virtual;

    /**
     * @dev 由不包含额外参数的 castVote 方法使用的默认额外编码参数
     *
     * 注意：具体实现应覆盖此方法以使用适当的值，在该实现的上下文中，额外参数的含义。
     */
    function _defaultParams() internal view virtual returns (bytes memory) {
        return "";
    }

    /**
     * @dev 查看 {IGovernor-propose}。此函数具有选择性的前跑保护，描述在 {_isValidDescriptionForProposer} 中。
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual returns (uint256) {
        address proposer = _msgSender();

        // 检查描述限制
        if (!_isValidDescriptionForProposer(proposer, description)) {
            revert GovernorRestrictedProposer(proposer);
        }

        // 检查提案阈值
        uint256 proposerVotes = getVotes(proposer, clock() - 1);
        uint256 votesThreshold = proposalThreshold();
        if (proposerVotes < votesThreshold) {
            revert GovernorInsufficientProposerVotes(
                proposer,
                proposerVotes,
                votesThreshold
            );
        }

        return _propose(targets, values, calldatas, description, proposer);
    }

    /**
     * @dev 内部提案机制。可以覆盖以在提案创建时添加更多逻辑。
     *
     * 触发 {IGovernor-ProposalCreated} 事件。
     */
    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal virtual returns (uint256 proposalId) {
        proposalId = hashProposal(
            targets,
            values,
            calldatas,
            keccak256(bytes(description))
        );

        if (
            targets.length != values.length ||
            targets.length != calldatas.length ||
            targets.length == 0
        ) {
            revert GovernorInvalidProposalLength(
                targets.length,
                calldatas.length,
                values.length
            );
        }
        if (_proposals[proposalId].voteStart != 0) {
            revert GovernorUnexpectedProposalState(
                proposalId,
                state(proposalId),
                bytes32(0)
            );
        }

        uint256 snapshot = clock() + votingDelay();
        uint256 duration = votingPeriod();

        ProposalCore storage proposal = _proposals[proposalId];
        proposal.proposer = proposer;
        proposal.voteStart = SafeCast.toUint48(snapshot);
        proposal.voteDuration = SafeCast.toUint32(duration);

        emit ProposalCreated(
            proposalId,
            proposer,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            snapshot,
            snapshot + duration,
            description
        );

        // 使用命名返回变量以避免堆栈过深错误
    }

    /**
     * @dev 查看 {IGovernor-queue}。
     */
    function queue(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public virtual returns (uint256) {
        uint256 proposalId = hashProposal(
            targets,
            values,
            calldatas,
            descriptionHash
        );

        _validateStateBitmap(
            proposalId,
            _encodeStateBitmap(ProposalState.Succeeded)
        );

        uint48 etaSeconds = _queueOperations(
            proposalId,
            targets,
            values,
            calldatas,
            descriptionHash
        );

        if (etaSeconds != 0) {
            _proposals[proposalId].etaSeconds = etaSeconds;
            emit ProposalQueued(proposalId, etaSeconds);
        } else {
            revert GovernorQueueNotImplemented();
        }

        return proposalId;
    }

    /**
     * @dev 内部队列机制。可以覆盖（无需 super 调用）以修改队列执行的方式（例如添加金库/时间锁）。
     *
     * 默认情况下这是空的，必须覆盖以实现队列功能。
     *
     * 此函数返回描述执行预期 ETA 的时间戳。如果返回值为 0（默认值），核心将认为队列未成功，公共 {queue} 函数将还原。
     *
     * 注意：直接调用此函数不会检查提案的当前状态，也不会触发 `ProposalQueued` 事件。应使用 {queue} 来队列提案。
     */
    function _queueOperations(
        uint256 /*proposalId*/,
        address[] memory /*targets*/,
        uint256[] memory /*values*/,
        bytes[] memory /*calldatas*/,
        bytes32 /*descriptionHash*/
    ) internal virtual returns (uint48) {
        return 0;
    }

    /**
     * @dev 查看 {IGovernor-execute}。
     */
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable virtual returns (uint256) {
        uint256 proposalId = hashProposal(
            targets,
            values,
            calldatas,
            descriptionHash
        );

        _validateStateBitmap(
            proposalId,
            _encodeStateBitmap(ProposalState.Succeeded) |
                _encodeStateBitmap(ProposalState.Queued)
        );

        // 在调用之前标记为已执行以避免重入
        _proposals[proposalId].executed = true;

        // 执行之前：将治理调用注册到队列中。
        if (_executor() != address(this)) {
            for (uint256 i = 0; i < targets.length; ++i) {
                if (targets[i] == address(this)) {
                    _governanceCall.pushBack(keccak256(calldatas[i]));
                }
            }
        }

        _executeOperations(
            proposalId,
            targets,
            values,
            calldatas,
            descriptionHash
        );

        // 执行之后：清理治理调用队列。
        if (_executor() != address(this) && !_governanceCall.empty()) {
            _governanceCall.clear();
        }

        emit ProposalExecuted(proposalId);

        return proposalId;
    }

    /**
     * @dev 内部执行机制。可以覆盖（无需 super 调用）以修改执行的方式（例如添加金库/时间锁）。
     *
     * 注意：直接调用此函数不会检查提案的当前状态、将已执行标志设置为 true 或触发 `ProposalExecuted` 事件。应使用 {execute} 或 {_execute} 执行提案。
     */
    function _executeOperations(
        uint256 /* proposalId */,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 /*descriptionHash*/
    ) internal virtual {
        for (uint256 i = 0; i < targets.length; ++i) {
            (bool success, bytes memory returndata) = targets[i].call{
                value: values[i]
            }(calldatas[i]);
            Address.verifyCallResult(success, returndata);
        }
    }

    /**
     * @dev 查看 {IGovernor-cancel}。
     */
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public virtual returns (uint256) {
        // proposalId 将在稍后的 `_cancel` 调用中重新计算。但是我们需要在内部调用之前获得该值，因为我们需要在内部 `_cancel` 调用更改之前检查提案状态。
        // `hashProposal` 的重复成本是有限的，我们接受这个成本。
        uint256 proposalId = hashProposal(
            targets,
            values,
            calldatas,
            descriptionHash
        );

        // 公开取消限制（在现有的 _cancel 限制之上）。
        _validateStateBitmap(
            proposalId,
            _encodeStateBitmap(ProposalState.Pending)
        );
        if (_msgSender() != proposalProposer(proposalId)) {
            revert GovernorOnlyProposer(_msgSender());
        }

        return _cancel(targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev 内部取消机制，限制最少。提案可以在任何状态下取消，除了已取消、已过期或已执行。一旦取消，提案不能重新提交。
     *
     * 触发 {IGovernor-ProposalCanceled} 事件。
     */
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual returns (uint256) {
        uint256 proposalId = hashProposal(
            targets,
            values,
            calldatas,
            descriptionHash
        );

        _validateStateBitmap(
            proposalId,
            ALL_PROPOSAL_STATES_BITMAP ^
                _encodeStateBitmap(ProposalState.Canceled) ^
                _encodeStateBitmap(ProposalState.Expired) ^
                _encodeStateBitmap(ProposalState.Executed)
        );

        _proposals[proposalId].canceled = true;
        emit ProposalCanceled(proposalId);

        return proposalId;
    }

    /**
     * @dev 查看 {IGovernor-getVotes}。
     */
    function getVotes(
        address account,
        uint256 timepoint
    ) public view virtual returns (uint256) {
        return _getVotes(account, timepoint, _defaultParams());
    }

    /**
     * @dev 查看 {IGovernor-getVotesWithParams}。
     */
    function getVotesWithParams(
        address account,
        uint256 timepoint,
        bytes memory params
    ) public view virtual returns (uint256) {
        return _getVotes(account, timepoint, params);
    }

    /**
     * @dev 查看 {IGovernor-castVote}。
     */
    function castVote(
        uint256 proposalId,
        uint8 support
    ) public virtual returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, "");
    }

    /**
     * @dev 查看 {IGovernor-castVoteWithReason}。
     */
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public virtual returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason);
    }

    /**
     * @dev 查看 {IGovernor-castVoteWithReasonAndParams}。
     */
    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) public virtual returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason, params);
    }

    /**
     * @dev 查看 {IGovernor-castVoteBySig}。
     */
    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        address voter,
        bytes memory signature
    ) public virtual returns (uint256) {
        bool valid = SignatureChecker.isValidSignatureNow(
            voter,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        BALLOT_TYPEHASH,
                        proposalId,
                        support,
                        voter,
                        _useNonce(voter)
                    )
                )
            ),
            signature
        );

        if (!valid) {
            revert GovernorInvalidSignature(voter);
        }

        return _castVote(proposalId, voter, support, "");
    }

    /**
     * @dev 查看 {IGovernor-castVoteWithReasonAndParamsBySig}。
     */
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        address voter,
        string calldata reason,
        bytes memory params,
        bytes memory signature
    ) public virtual returns (uint256) {
        bool valid = SignatureChecker.isValidSignatureNow(
            voter,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EXTENDED_BALLOT_TYPEHASH,
                        proposalId,
                        support,
                        voter,
                        _useNonce(voter),
                        keccak256(bytes(reason)),
                        keccak256(params)
                    )
                )
            ),
            signature
        );

        if (!valid) {
            revert GovernorInvalidSignature(voter);
        }

        return _castVote(proposalId, voter, support, reason, params);
    }

    /**
     * @dev 内部投票机制：检查投票是否待处理，是否尚未投票，使用 {IGovernor-getVotes} 检索投票权重并调用内部函数 {_countVote}。
     * 使用 _defaultParams()。
     *
     * 触发 {IGovernor-VoteCast} 事件。
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason
    ) internal virtual returns (uint256) {
        return
            _castVote(proposalId, account, support, reason, _defaultParams());
    }

    /**
     * @dev 内部投票机制：检查投票是否待处理，是否尚未投票，使用 {IGovernor-getVotes} 检索投票权重并调用内部函数 {_countVote}。
     *
     * 触发 {IGovernor-VoteCast} 事件。
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual returns (uint256) {
        _validateStateBitmap(
            proposalId,
            _encodeStateBitmap(ProposalState.Active)
        );

        uint256 weight = _getVotes(
            account,
            proposalSnapshot(proposalId),
            params
        );
        _countVote(proposalId, account, support, weight, params);

        if (params.length == 0) {
            emit VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit VoteCastWithParams(
                account,
                proposalId,
                support,
                weight,
                reason,
                params
            );
        }

        return weight;
    }

    /**
     * @dev 将交易或函数调用中继到任意目标。在治理执行者是治理者本身以外的合约的情况下（例如使用时间锁），
     * 此函数可以在治理提案中调用，以恢复因错误发送到治理者合约的代币或以太币。
     * 注意，如果执行者只是治理者本身，则使用 `relay` 是多余的。
     */
    function relay(
        address target,
        uint256 value,
        bytes calldata data
    ) external payable virtual onlyGovernance {
        (bool success, bytes memory returndata) = target.call{ value: value }(
            data
        );
        Address.verifyCallResult(success, returndata);
    }

    /**
     * @dev 治理者执行动作的地址。将被模块覆盖，通过另一个合约（例如时间锁）执行操作。
     */
    function _executor() internal view virtual returns (address) {
        return address(this);
    }

    /**
     * @dev 查看 {IERC721Receiver-onERC721Received}。
     * 如果治理执行者不是治理者本身（例如使用时间锁），则禁用接收代币。
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        if (_executor() != address(this)) {
            revert GovernorDisabledDeposit();
        }
        return this.onERC721Received.selector;
    }

    /**
     * @dev 查看 {IERC1155Receiver-onERC1155Received}。
     * 如果治理执行者不是治理者本身（例如使用时间锁），则禁用接收代币。
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        if (_executor() != address(this)) {
            revert GovernorDisabledDeposit();
        }
        return this.onERC1155Received.selector;
    }

    /**
     * @dev 查看 {IERC1155Receiver-onERC1155BatchReceived}。
     * 如果治理执行者不是治理者本身（例如使用时间锁），则禁用接收代币。
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bytes4) {
        if (_executor() != address(this)) {
            revert GovernorDisabledDeposit();
        }
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev 将 `ProposalState` 编码为 `bytes32` 表示，其中每个启用的位对应于 `ProposalState` 枚举中的底层位置。例如：
     *
     * 0x000...10000
     *   ^^^^^^------ ...
     *         ^----- 成功
     *          ^---- 失败
     *           ^--- 已取消
     *            ^-- 活跃
     *             ^- 待处理
     */
    function _encodeStateBitmap(
        ProposalState proposalState
    ) internal pure returns (bytes32) {
        return bytes32(1 << uint8(proposalState));
    }

    /**
     * @dev 检查提案的当前状态是否符合 `allowedStates` 位图所描述的要求。此位图应使用 `_encodeStateBitmap` 构建。
     *
     * 如果不满足要求，则使用 {GovernorUnexpectedProposalState} 错误还原。
     */
    function _validateStateBitmap(
        uint256 proposalId,
        bytes32 allowedStates
    ) private view returns (ProposalState) {
        ProposalState currentState = state(proposalId);
        if (_encodeStateBitmap(currentState) & allowedStates == bytes32(0)) {
            revert GovernorUnexpectedProposalState(
                proposalId,
                currentState,
                allowedStates
            );
        }
        return currentState;
    }

    /*
     * @dev 检查提案人是否有权提交带有给定描述的提案。
     *
     * 如果提案描述以 `#proposer=0x???` 结尾，其中 `0x???` 是作为十六进制字符串写的地址（不区分大小写），
     * 则该提案的提交将仅授权给该地址。
     *
     * 这用于防止抢跑。通过在其提案末尾添加此模式，可以确保没有其他地址可以提交相同的提案。
     * 攻击者必须删除或更改该部分，这将导致不同

的提案 ID。
     *
     * 如果描述不匹配此模式，则不受限制，任何人都可以提交。这包括：
     * - 如果 `0x???` 部分不是有效的十六进制字符串。
     * - 如果 `0x???` 部分是有效的十六进制字符串，但不包含恰好 40 个十六进制数字。
     * - 如果它以预期的后缀结尾，后面是换行符或其他空格。
     * - 如果它以其他类似后缀结尾，例如 `#other=abc`。
     * - 如果它没有以任何此类后缀结尾。
     */
    function _isValidDescriptionForProposer(
        address proposer,
        string memory description
    ) internal view virtual returns (bool) {
        uint256 len = bytes(description).length;

        // 长度太短，无法包含有效的提案人后缀
        if (len < 52) {
            return true;
        }

        // 提取将是 `#proposer=0x` 标记开始的后缀
        bytes12 marker;
        assembly {
            // - 字符串内容在内存中的起始位置 = description + 32
            // - 标记的第一个字符 = len - 52
            //   - 长度为 "#proposer=0x0000000000000000000000000000000000000000" 的字符串 = 52
            // - 我们从标记的第一个字符开始读取内存字：
            //   - (description + 32) + (len - 52) = description + (len - 20)
            // - 注意：Solidity 将忽略前 12 个字节后的任何内容
            marker := mload(add(description, sub(len, 20)))
        }

        // 如果未找到标记，则没有提案人后缀需要检查
        if (marker != bytes12("#proposer=0x")) {
            return true;
        }

        // 将标记后面的 40 个字符解析为 uint160
        uint160 recovered = 0;
        for (uint256 i = len - 40; i < len; ++i) {
            (bool isHex, uint8 value) = _tryHexToUint(bytes(description)[i]);
            // 如果任何字符不是十六进制数字，则完全忽略后缀
            if (!isHex) {
                return true;
            }
            recovered = (recovered << 4) | value;
        }

        return recovered == uint160(proposer);
    }

    /**
     * @dev 尝试将字符串中的字符解析为十六进制值。
     * 如果字符在 `[0-9a-fA-F]` 范围内，则返回 `(true, value)`，否则返回 `(false, 0)`。
     * 值保证在 `0 <= value < 16` 范围内。
     */
    function _tryHexToUint(bytes1 char) private pure returns (bool, uint8) {
        uint8 c = uint8(char);
        unchecked {
            // 情况 0-9
            if (47 < c && c < 58) {
                return (true, c - 48);
            }
            // 情况 A-F
            else if (64 < c && c < 71) {
                return (true, c - 55);
            }
            // 情况 a-f
            else if (96 < c && c < 103) {
                return (true, c - 87);
            }
            // 否则：不是十六进制字符
            else {
                return (false, 0);
            }
        }
    }

    /**
     * @inheritdoc IERC6372
     */
    function clock() public view virtual returns (uint48);

    /**
     * @inheritdoc IERC6372
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual returns (string memory);

    /**
     * @inheritdoc IGovernor
     */
    function votingDelay() public view virtual returns (uint256);

    /**
     * @inheritdoc IGovernor
     */
    function votingPeriod() public view virtual returns (uint256);

    /**
     * @inheritdoc IGovernor
     */
    function quorum(uint256 timepoint) public view virtual returns (uint256);
}
