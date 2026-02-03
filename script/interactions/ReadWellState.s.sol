// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {WellOfReflection} from "../../src/WellOfReflection.sol";

/**
 * @title ReadWellState
 * @notice Reads WellOfReflection state and prints JSON to console.
 */
contract ReadWellState is Script {
    function run() external view {
        string memory network;
        try vm.envString("NETWORK") returns (string memory _network) {
            network = _network;
        } catch {
            revert("NETWORK not set. Use NETWORK=testnet or NETWORK=mainnet");
        }

        address wellAddr;
        bytes32 networkHash = keccak256(bytes(network));
        if (networkHash == keccak256(bytes("testnet"))) {
            try vm.envAddress("WELL_ADDRESS_TESTNET") returns (address _addr) {
                wellAddr = _addr;
            } catch {
                revert("WELL_ADDRESS_TESTNET not set in .env");
            }
        } else if (networkHash == keccak256(bytes("mainnet"))) {
            try vm.envAddress("WELL_ADDRESS_MAINNET") returns (address _addr) {
                wellAddr = _addr;
            } catch {
                revert("WELL_ADDRESS_MAINNET not set in .env");
            }
        } else {
            revert("NETWORK must be testnet or mainnet");
        }

        WellOfReflection well = WellOfReflection(payable(wellAddr));

        uint16 requestConfirmations = well.REQUEST_CONFIRMATIONS();
        uint32 callbackGasLimit = well.CALLBACK_GAS_LIMIT();
        uint32 numWords = well.NUM_OF_WORDS();
        uint256 offeringAmount = well.OFFERING_AMOUNT();
        uint256 reflectionModulus = well.REFLECTION_MODULUS();
        uint256 currentWellId = well.currentWellId();
        bool wellIsReady = well.wellIsReadyToReceive();
        uint256 vrfFee = well.quoteVrfFee();

        string memory json = string.concat(
            "{\n",
            '    "well": "',
            vm.toString(wellAddr),
            '",\n',
            '    "REQUEST_CONFIRMATIONS": ',
            vm.toString(uint256(requestConfirmations)),
            ",\n",
            '    "CALLBACK_GAS_LIMIT": ',
            vm.toString(uint256(callbackGasLimit)),
            ",\n",
            '    "NUM_OF_WORDS": ',
            vm.toString(uint256(numWords)),
            ",\n",
            '    "OFFERING_AMOUNT": ',
            vm.toString(offeringAmount),
            ",\n",
            '    "REFLECTION_MODULUS": ',
            vm.toString(reflectionModulus),
            ",\n",
            '    "currentWellId": ',
            vm.toString(currentWellId),
            ",\n",
            '    "wellIsReadyToReceive": ',
            (wellIsReady ? "true" : "false"),
            ",\n",
            '    "quoteVrfFee": ',
            vm.toString(vrfFee),
            "\n  }"
        );

        console2.log(json);
    }
}
