// SPDX-License-Identifier: CAL
pragma solidity ^0.8.18;

import {SignedContextV1} from "rain.interpreter/src/interface/IInterpreterCallerV2.sol";
import {Evaluable, EvaluableConfigV2} from "rain.interpreter/src/lib/caller/LibEvaluable.sol";

import {FlowERC20IOV1, ERC20SupplyChange} from "../IFlowERC20V3.sol";

/// Constructor config.
/// @param name As per Open Zeppelin `ERC20Upgradeable`.
/// @param symbol As per Open Zeppelin `ERC20Upgradeable`.
struct FlowERC20ConfigV2 {
    string name;
    string symbol;
    EvaluableConfigV2 evaluableConfig;
    EvaluableConfigV2[] flowConfig;
}

interface IFlowERC20V4 {
    event Initialize(address sender, FlowERC20ConfigV2 config);

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
