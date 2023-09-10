// SPDX-License-Identifier: CAL
pragma solidity =0.8.19;

import {ERC20Upgradeable as ERC20} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable as ReentrancyGuard} from
    "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";

import "rain.interpreter/src/interface/IExpressionDeployerV1.sol";
import "rain.solmem/lib/LibUint256Array.sol";
import "rain.solmem/lib/LibUint256Matrix.sol";
import "rain.interpreter/src/lib/caller/LibEncodedDispatch.sol";
import "rain.factory/src/interface/ICloneableV2.sol";
import "../../interface/unstable/IFlowERC20V4.sol";
import "rain.solmem/lib/LibStackSentinel.sol";
import "lib/rain.interpreter/src/lib/bytecode/LibBytecode.sol";

import "../../lib/LibFlow.sol";
import "rain.math.fixedpoint/lib/LibFixedPointDecimalArithmeticOpenZeppelin.sol";
import "../../abstract/FlowCommon.sol";

bytes32 constant CALLER_META_HASH = bytes32(0xff0499e4ee7171a54d176cfe13165a7ea512d146dbd99d42b3d3ec9963025acf);

Sentinel constant RAIN_FLOW_ERC20_SENTINEL =
    Sentinel.wrap(uint256(keccak256(bytes("RAIN_FLOW_ERC20_SENTINEL")) | SENTINEL_HIGH_BITS));

SourceIndex constant HANDLE_TRANSFER_ENTRYPOINT = SourceIndex.wrap(0);
uint256 constant HANDLE_TRANSFER_MIN_OUTPUTS = 0;
uint16 constant HANDLE_TRANSFER_MAX_OUTPUTS = 0;

/// @title FlowERC20
contract FlowERC20 is ICloneableV2, IFlowERC20V4, ReentrancyGuard, FlowCommon, ERC20 {
    using LibStackSentinel for Pointer;
    using LibStackPointer for uint256[];
    using LibStackPointer for Pointer;
    using LibUint256Array for uint256;
    using LibUint256Array for uint256[];
    using LibUint256Matrix for uint256[];
    using LibFixedPointDecimalArithmeticOpenZeppelin for uint256;

    bool private evalHandleTransfer;
    Evaluable internal evaluable;

    constructor(DeployerDiscoverableMetaV2ConstructionConfig memory config) FlowCommon(CALLER_META_HASH, config) {}

    /// @inheritdoc ICloneableV2
    function initialize(bytes calldata data) external initializer returns (bytes32) {
        FlowERC20ConfigV2 memory flowERC20Config = abi.decode(data, (FlowERC20ConfigV2));
        emit Initialize(msg.sender, flowERC20Config);
        __ReentrancyGuard_init();
        __ERC20_init(flowERC20Config.name, flowERC20Config.symbol);

        flowCommonInit(flowERC20Config.flowConfig, MIN_FLOW_SENTINELS + 2);

        if (
            LibBytecode.sourceCount(flowERC20Config.evaluableConfig.bytecode) > 0
                && LibBytecode.sourceOpsLength(
                    flowERC20Config.evaluableConfig.bytecode, SourceIndex.unwrap(HANDLE_TRANSFER_ENTRYPOINT)
                ) > 0
        ) {
            evalHandleTransfer = true;
            (IInterpreterV1 interpreter, IInterpreterStoreV1 store, address expression) = flowERC20Config
                .evaluableConfig
                .deployer
                .deployExpression(
                flowERC20Config.evaluableConfig.bytecode,
                flowERC20Config.evaluableConfig.constants,
                LibUint256Array.arrayFrom(HANDLE_TRANSFER_MIN_OUTPUTS)
            );
            evaluable = Evaluable(interpreter, store, expression);
        }

        return ICLONEABLE_V2_SUCCESS;
    }

    function _dispatchHandleTransfer(address expression_) internal pure returns (EncodedDispatch) {
        return LibEncodedDispatch.encode(expression_, HANDLE_TRANSFER_ENTRYPOINT, HANDLE_TRANSFER_MAX_OUTPUTS);
    }

    /// @inheritdoc ERC20
    function _afterTokenTransfer(address from_, address to_, uint256 amount_) internal virtual override {
        unchecked {
            super._afterTokenTransfer(from_, to_, amount_);

            // Mint and burn access MUST be handled by flow.
            // HANDLE_TRANSFER will only restrict subsequent transfers.
            if (evalHandleTransfer && !(from_ == address(0) || to_ == address(0))) {
                Evaluable memory evaluable_ = evaluable;
                (, uint256[] memory kvs_) = evaluable_.interpreter.eval(
                    evaluable_.store,
                    DEFAULT_STATE_NAMESPACE,
                    _dispatchHandleTransfer(evaluable_.expression),
                    LibContext.build(
                        // The transfer params are caller context because the caller
                        // is triggering the transfer.
                        LibUint256Array.arrayFrom(uint256(uint160(from_)), uint256(uint160(to_)), amount_).matrixFrom(),
                        new SignedContextV1[](0)
                    )
                );
                if (kvs_.length > 0) {
                    evaluable_.store.set(DEFAULT_STATE_NAMESPACE, kvs_);
                }
            }
        }
    }

    function _previewFlow(Evaluable memory evaluable_, uint256[][] memory context_)
        internal
        view
        virtual
        returns (FlowERC20IOV1 memory, uint256[] memory)
    {
        ERC20SupplyChange[] memory mints_;
        ERC20SupplyChange[] memory burns_;
        Pointer tuplesPointer_;
        (Pointer stackBottom_, Pointer stackTop_, uint256[] memory kvs_) = flowStack(evaluable_, context_);
        // mints
        (stackTop_, tuplesPointer_) = stackBottom_.consumeSentinelTuples(stackTop_, RAIN_FLOW_ERC20_SENTINEL, 2);
        assembly ("memory-safe") {
            mints_ := tuplesPointer_
        }
        // burns
        (stackTop_, tuplesPointer_) = stackBottom_.consumeSentinelTuples(stackTop_, RAIN_FLOW_ERC20_SENTINEL, 2);
        assembly ("memory-safe") {
            burns_ := tuplesPointer_
        }

        return (FlowERC20IOV1(mints_, burns_, LibFlow.stackToFlow(stackBottom_, stackTop_)), kvs_);
    }

    function _flow(
        Evaluable memory evaluable_,
        uint256[] memory callerContext_,
        SignedContextV1[] memory signedContexts_
    ) internal virtual nonReentrant returns (FlowERC20IOV1 memory) {
        unchecked {
            uint256[][] memory context_ = LibContext.build(callerContext_.matrixFrom(), signedContexts_);
            emit Context(msg.sender, context_);
            (FlowERC20IOV1 memory flowIO_, uint256[] memory kvs_) = _previewFlow(evaluable_, context_);
            for (uint256 i_ = 0; i_ < flowIO_.mints.length; i_++) {
                _mint(flowIO_.mints[i_].account, flowIO_.mints[i_].amount);
            }
            for (uint256 i_ = 0; i_ < flowIO_.burns.length; i_++) {
                _burn(flowIO_.burns[i_].account, flowIO_.burns[i_].amount);
            }
            LibFlow.flow(flowIO_.flow, evaluable_.store, kvs_);
            return flowIO_;
        }
    }

    function previewFlow(
        Evaluable memory evaluable_,
        uint256[] memory callerContext_,
        SignedContextV1[] memory signedContexts_
    ) external view virtual returns (FlowERC20IOV1 memory) {
        uint256[][] memory context_ = LibContext.build(callerContext_.matrixFrom(), signedContexts_);
        (FlowERC20IOV1 memory flowERC20IO_,) = _previewFlow(evaluable_, context_);
        return flowERC20IO_;
    }

    function flow(
        Evaluable memory evaluable_,
        uint256[] memory callerContext_,
        SignedContextV1[] memory signedContexts_
    ) external virtual returns (FlowERC20IOV1 memory) {
        return _flow(evaluable_, callerContext_, signedContexts_);
    }
}
