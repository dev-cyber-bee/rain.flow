// SPDX-License-Identifier: CAL
pragma solidity ^0.8.18;

import "rain.interpreter/src/interface/IInterpreterCallerV2.sol";
import "rain.interpreter/src/lib/caller/LibEvaluable.sol";
import {Sentinel} from "rain.solmem/lib/LibStackSentinel.sol";
import "./IFlowV3.sol";

Sentinel constant RAIN_FLOW_ERC20_SENTINEL =
    Sentinel.wrap(uint256(keccak256(bytes("RAIN_FLOW_ERC20_SENTINEL")) | SENTINEL_HIGH_BITS));

SourceIndex constant FLOW_ERC20_HANDLE_TRANSFER_ENTRYPOINT = SourceIndex.wrap(0);
uint256 constant FLOW_ERC20_HANDLE_TRANSFER_MIN_OUTPUTS = 0;
uint16 constant FLOW_ERC20_HANDLE_TRANSFER_MAX_OUTPUTS = 0;

struct ERC20SupplyChange {
    address account;
    uint256 amount;
}

struct FlowERC20IOV1 {
    ERC20SupplyChange[] mints;
    ERC20SupplyChange[] burns;
    FlowTransferV1 flow;
}

/// Constructor config.
/// @param Constructor config for the ERC20 token minted according to flow
/// schedule in `flow`.
/// @param Constructor config for the `ImmutableSource` that defines the
/// emissions schedule for claiming.
struct FlowERC20Config {
    string name;
    string symbol;
    EvaluableConfig evaluableConfig;
    EvaluableConfig[] flowConfig;
}

/// @title IFlowERC20V3
/// @notice Mints itself according to some predefined schedule. The schedule is
/// expressed as an expression and the `claim` function is world-callable.
/// Intended behaviour is to avoid sybils infinitely minting by putting the
/// claim functionality behind a `TierV2` contract. The flow contract
/// itself implements `ReadOnlyTier` and every time a claim is processed it
/// logs the block number of the claim against every tier claimed. So the block
/// numbers in the tier report for `FlowERC20` are the last time that tier
/// was claimed against this contract. The simplest way to make use of this
/// information is to take the max block for the underlying tier and the last
/// claim and then diff it against the current block number.
/// See `test/Claim/FlowERC20.sol.ts` for examples, including providing
/// staggered rewards where more tokens are minted for higher tier accounts.
interface IFlowERC20V3 {
    /// Contract has initialized.
    /// @param sender `msg.sender` initializing the contract (factory).
    /// @param config All initialized config.
    event Initialize(address sender, FlowERC20Config config);

    function previewFlow(
        Evaluable calldata evaluable,
        uint256[] calldata callerContext,
        SignedContextV1[] calldata signedContexts
    ) external view returns (FlowERC20IOV1 calldata);

    function flow(
        Evaluable calldata evaluable,
        uint256[] calldata callerContext,
        SignedContextV1[] calldata signedContexts
    ) external returns (FlowERC20IOV1 calldata);
}
