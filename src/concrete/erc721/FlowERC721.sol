// SPDX-License-Identifier: CAL
pragma solidity =0.8.19;

import {ERC721Upgradeable as ERC721} from "openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {ERC1155ReceiverUpgradeable as ERC1155Receiver} from "openzeppelin-contracts-upgradeable/contracts/token/ERC1155/utils/ERC1155ReceiverUpgradeable.sol";

import "rain.interpreter/src/interface/IExpressionDeployerV1.sol";
import "rain.solmem/lib/LibUint256Array.sol";
import "rain.solmem/lib/LibUint256Matrix.sol";
import "rain.solmem/lib/LibStackSentinel.sol";
import "rain.interpreter/src/lib/caller/LibEncodedDispatch.sol";
import "rain.factory/src/interface/ICloneableV2.sol";
import "../../interface/unstable/IFlowERC721V4.sol";

import "../../lib/LibFlow.sol";
import "rain.math.fixedpoint/lib/LibFixedPointDecimalArithmeticOpenZeppelin.sol";
import {FlowCommon, DeployerDiscoverableMetaV2ConstructionConfig, LibContext, MIN_FLOW_SENTINELS} from "../../abstract/FlowCommon.sol";

/// Thrown when burner of tokens is not the owner of tokens.
error BurnerNotOwner();

Sentinel constant RAIN_FLOW_ERC721_SENTINEL = Sentinel.wrap(
    uint256(keccak256(bytes("RAIN_FLOW_ERC721_SENTINEL")) | SENTINEL_HIGH_BITS)
);

bytes32 constant CALLER_META_HASH = bytes32(
    0x7f7944a4b89741668c06a27ffde94e19be970cd0506786de91aee01c2893d4ef
);

SourceIndex constant HANDLE_TRANSFER_ENTRYPOINT = SourceIndex.wrap(0);
SourceIndex constant TOKEN_URI_ENTRYPOINT = SourceIndex.wrap(1);
uint256 constant HANDLE_TRANSFER_MIN_OUTPUTS = 0;
uint256 constant TOKEN_URI_MIN_OUTPUTS = 1;
uint16 constant HANDLE_TRANSFER_MAX_OUTPUTS = 0;
uint16 constant TOKEN_URI_MAX_OUTPUTS = 1;

/// @title FlowERC721
contract FlowERC721 is
    ICloneableV2,
    IFlowERC721V4,
    ReentrancyGuard,
    FlowCommon,
    ERC721
{
    using LibStackPointer for uint256[];
    using LibStackPointer for Pointer;
    using LibUint256Array for uint256;
    using LibUint256Array for uint256[];
    using LibUint256Matrix for uint256[];
    using LibFixedPointDecimalArithmeticOpenZeppelin for uint256;
    using LibStackSentinel for Pointer;

    bool private evalHandleTransfer;
    bool private evalTokenURI;
    Evaluable internal evaluable;
    string private baseURI;

    constructor(
        DeployerDiscoverableMetaV2ConstructionConfig memory config_
    ) FlowCommon(CALLER_META_HASH, config_) {}

    /// @inheritdoc ICloneableV2
    function initialize(bytes calldata data) external initializer returns (bytes32) {
        FlowERC721ConfigV2 memory config = abi.decode(data, (FlowERC721ConfigV2));
        emit Initialize(msg.sender, config);
        __ReentrancyGuard_init();
        __ERC721_init(config.name, config.symbol);
        baseURI = config.baseURI;
        flowCommonInit(config.flowConfig, MIN_FLOW_SENTINELS + 2);

        if (config.evaluableConfig.sources.length > 0) {
            evalHandleTransfer =
                config
                    .evaluableConfig
                    .sources[SourceIndex.unwrap(HANDLE_TRANSFER_ENTRYPOINT)]
                    .length >
                0;
            evalTokenURI =
                config.evaluableConfig.sources.length > 1 &&
                config
                    .evaluableConfig
                    .sources[SourceIndex.unwrap(TOKEN_URI_ENTRYPOINT)]
                    .length >
                0;

            (
                IInterpreterV1 interpreter,
                IInterpreterStoreV1 store,
                address expression
            ) = config.evaluableConfig.deployer.deployExpression(
                    config.evaluableConfig.bytecode,
                    config.evaluableConfig.constants,
                    LibUint256Array.arrayFrom(
                        HANDLE_TRANSFER_MIN_OUTPUTS,
                        TOKEN_URI_MIN_OUTPUTS
                    )
                );
            evaluable = Evaluable(interpreter, store, expression);
        }

        return ICLONEABLE_V2_SUCCESS;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function tokenURI(
        uint256 tokenId_
    ) public view virtual override returns (string memory) {
        if (evalTokenURI) {
            Evaluable memory evaluable_ = evaluable;
            (uint256[] memory stack_, ) = evaluable_.interpreter.eval(
                evaluable_.store,
                DEFAULT_STATE_NAMESPACE,
                _dispatchTokenURI(evaluable_.expression),
                LibContext.build(
                    LibUint256Array.arrayFrom(tokenId_).matrixFrom(),
                    new SignedContextV1[](0)
                )
            );
            tokenId_ = stack_[0];
        }

        return super.tokenURI(tokenId_);
    }

    function _dispatchHandleTransfer(
        address expression_
    ) internal pure returns (EncodedDispatch) {
        return
            LibEncodedDispatch.encode(
                expression_,
                HANDLE_TRANSFER_ENTRYPOINT,
                HANDLE_TRANSFER_MAX_OUTPUTS
            );
    }

    function _dispatchTokenURI(
        address expression_
    ) internal pure returns (EncodedDispatch) {
        return
            LibEncodedDispatch.encode(
                expression_,
                TOKEN_URI_ENTRYPOINT,
                TOKEN_URI_MAX_OUTPUTS
            );
    }

    /// Needed here to fix Open Zeppelin implementing `supportsInterface` on
    /// multiple base contracts.
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721, ERC1155Receiver) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc ERC721
    function _afterTokenTransfer(
        address from_,
        address to_,
        uint256 tokenId_,
        uint256 batchSize_
    ) internal virtual override {
        unchecked {
            super._afterTokenTransfer(from_, to_, tokenId_, batchSize_);

            // Mint and burn access MUST be handled by flow.
            // HANDLE_TRANSFER will only restrict subsequent transfers.
            if (
                evalHandleTransfer &&
                !(from_ == address(0) || to_ == address(0))
            ) {
                Evaluable memory evaluable_ = evaluable;
                (, uint256[] memory kvs_) = evaluable_.interpreter.eval(
                    evaluable_.store,
                    DEFAULT_STATE_NAMESPACE,
                    _dispatchHandleTransfer(evaluable_.expression),
                    LibContext.build(
                        // Transfer information.
                        // Does NOT include `batchSize_` because handle
                        // transfer is NOT called for mints.
                        LibUint256Array
                            .arrayFrom(
                                uint256(uint160(from_)),
                                uint256(uint160(to_)),
                                tokenId_
                            )
                            .matrixFrom(),
                        new SignedContextV1[](0)
                    )
                );
                if (kvs_.length > 0) {
                    evaluable_.store.set(DEFAULT_STATE_NAMESPACE, kvs_);
                }
            }
        }
    }

    function _previewFlow(
        Evaluable memory evaluable_,
        uint256[][] memory context_
    ) internal view returns (FlowERC721IOV1 memory, uint256[] memory) {
        ERC721SupplyChange[] memory mints_;
        ERC721SupplyChange[] memory burns_;
        Pointer tuplesPointer_;

        (
            Pointer stackBottom_,
            Pointer stackTop_,
            uint256[] memory kvs_
        ) = flowStack(evaluable_, context_);
        // mints
        (stackTop_, tuplesPointer_) = stackBottom_.consumeSentinelTuples(
            stackTop_,
            RAIN_FLOW_ERC721_SENTINEL,
            2
        );
        assembly ("memory-safe") {
            mints_ := tuplesPointer_
        }
        // burns
        (stackTop_, tuplesPointer_) = stackBottom_.consumeSentinelTuples(
            stackTop_,
            RAIN_FLOW_ERC721_SENTINEL,
            2
        );
        assembly ("memory-safe") {
            burns_ := tuplesPointer_
        }
        return (
            FlowERC721IOV1(
                mints_,
                burns_,
                LibFlow.stackToFlow(stackBottom_, stackTop_)
            ),
            kvs_
        );
    }

    function _flow(
        Evaluable memory evaluable_,
        uint256[] memory callerContext_,
        SignedContextV1[] memory signedContexts_
    ) internal virtual nonReentrant returns (FlowERC721IOV1 memory) {
        unchecked {
            uint256[][] memory context_ = LibContext.build(
                callerContext_.matrixFrom(),
                signedContexts_
            );
            emit Context(msg.sender, context_);
            (
                FlowERC721IOV1 memory flowIO_,
                uint256[] memory kvs_
            ) = _previewFlow(evaluable_, context_);
            for (uint256 i_ = 0; i_ < flowIO_.mints.length; i_++) {
                _safeMint(flowIO_.mints[i_].account, flowIO_.mints[i_].id);
            }
            for (uint256 i_ = 0; i_ < flowIO_.burns.length; i_++) {
                uint256 burnId_ = flowIO_.burns[i_].id;
                if (ERC721.ownerOf(burnId_) != flowIO_.burns[i_].account) {
                    revert BurnerNotOwner();
                }
                _burn(burnId_);
            }
            LibFlow.flow(flowIO_.flow, evaluable_.store, kvs_);
            return flowIO_;
        }
    }

    function previewFlow(
        Evaluable memory evaluable_,
        uint256[] memory callerContext_,
        SignedContextV1[] memory signedContexts_
    ) external view virtual returns (FlowERC721IOV1 memory) {
        uint256[][] memory context_ = LibContext.build(
            callerContext_.matrixFrom(),
            signedContexts_
        );
        (FlowERC721IOV1 memory flowERC721IO_, ) = _previewFlow(
            evaluable_,
            context_
        );
        return flowERC721IO_;
    }

    function flow(
        Evaluable memory evaluable_,
        uint256[] memory callerContext_,
        SignedContextV1[] memory signedContexts_
    ) external virtual returns (FlowERC721IOV1 memory) {
        return _flow(evaluable_, callerContext_, signedContexts_);
    }
}
