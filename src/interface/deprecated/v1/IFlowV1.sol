// SPDX-License-Identifier: CAL
pragma solidity ^0.8.18;

import "rain.interpreter.interface/interface/deprecated/IInterpreterCallerV1.sol";
import "rain.interpreter.interface/lib/caller/LibEvaluable.sol";

struct FlowConfig {
    // https://github.com/ethereum/solidity/issues/13597
    EvaluableConfig dummyConfig;
    EvaluableConfig[] config;
}

struct NativeTransfer {
    address from;
    address to;
    uint256 amount;
}

struct ERC20Transfer {
    address token;
    address from;
    address to;
    uint256 amount;
}

struct ERC721Transfer {
    address token;
    address from;
    address to;
    uint256 id;
}

struct ERC1155Transfer {
    address token;
    address from;
    address to;
    uint256 id;
    uint256 amount;
}

struct FlowTransfer {
    NativeTransfer[] native;
    ERC20Transfer[] erc20;
    ERC721Transfer[] erc721;
    ERC1155Transfer[] erc1155;
}

interface IFlowV1 {
    event Initialize(address sender, FlowConfig config);

    function previewFlow(
        Evaluable calldata evaluable,
        uint256[] calldata callerContext,
        SignedContext[] calldata signedContexts
    ) external view returns (FlowTransfer calldata flowTransfer);

    function flow(
        Evaluable calldata evaluable,
        uint256[] calldata callerContext,
        SignedContext[] calldata signedContexts
    ) external payable returns (FlowTransfer calldata flowTransfer);
}
