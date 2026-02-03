// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {VRFV2PlusWrapper} from "@chainlink/vrf/dev/VRFV2PlusWrapper.sol";
import {WellOfReflection} from "../src/WellOfReflection.sol";

/**
 * @title DeployWell
 * @notice Deploys WellOfReflection contract.
 * @dev On local (chainId 31337): Also deploys wrapper using infra from DeployInfra.
 *      On testnet/mainnet: Uses VRF_WRAPPER env var for existing wrapper.
 *
 * Local usage:
 *   make deploy-infra   # First deploy infrastructure
 *   make deploy         # Then deploy wrapper + well
 *
 * Testnet usage:
 *   VRF_WRAPPER=0x... make deploy
 */
contract DeployWell is Script {
    using stdJson for string;

    function run() external {
        uint256 pk;
        address deployer;
        bool isLocal = block.chainid == 31337;

        if (isLocal) {
            try vm.envUint("ANVIL_PRIVATE_KEY") returns (uint256 _pk) {
                pk = _pk;
            } catch {
                revert("ANVIL_PRIVATE_KEY not set in .env");
            }
            deployer = vm.addr(pk);
        } else {
            pk = vm.envUint("PRIVATE_KEY");
            deployer = vm.addr(pk);
        }

        address wrapperAddr;
        address coordinatorAddr;

        if (isLocal) {
            // Read infrastructure from DeployInfra output
            string memory infraPath = "deployments/infra.json";
            string memory infraJson = vm.readFile(infraPath);
            address linkAddr = infraJson.readAddress(".link");
            address linkNativeFeedAddr = infraJson.readAddress(".linkNativeFeed");
            coordinatorAddr = infraJson.readAddress(".coordinator");

            // Read subscription ID from environment (set by Makefile after parsing logs)
            uint256 subId = vm.envUint("SUB_ID");
            require(subId != 0, "SUB_ID env var required - run 'make deploy' not 'forge script'");

            console2.log("=== Deploying Wrapper and Well (Local) ===");
            console2.log("Coordinator:", coordinatorAddr);
            console2.log("SubId:", subId);

            VRFCoordinatorV2_5Mock coordinator = VRFCoordinatorV2_5Mock(coordinatorAddr);

            vm.startBroadcast(pk);

            // Deploy wrapper
            VRFV2PlusWrapper wrapper = new VRFV2PlusWrapper(linkAddr, linkNativeFeedAddr, coordinatorAddr, subId);

            wrapper.setConfig(
                60000, // wrapperGasOverhead
                52000, // coordinatorGasOverheadNative
                150400, // coordinatorGasOverheadLink
                435, // coordinatorGasOverheadPerWord
                10, // nativePremiumPercentage
                50, // linkPremiumPercentage
                0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc, // keyHash (mock)
                10, // maxNumWords
                3600, // stalenessSeconds
                5e16, // fallbackWeiPerUnitLink
                0, // fulfillmentFlatFeeNativePPM
                0 // fulfillmentFlatFeeLinkDiscountPPM
            );

            coordinator.addConsumer(subId, address(wrapper));
            coordinator.fundSubscriptionWithNative{value: 100 ether}(subId);

            wrapperAddr = address(wrapper);
            console2.log("Wrapper:", wrapperAddr);
        } else {
            // Testnet/mainnet: use existing wrapper
            wrapperAddr = vm.envAddress("VRF_WRAPPER");
            console2.log("=== Deploying Well (Remote) ===");
            console2.log("Using wrapper:", wrapperAddr);

            vm.startBroadcast(pk);
        }

        // Deploy Well
        WellOfReflection well = new WellOfReflection(wrapperAddr);

        vm.stopBroadcast();

        // Write deployment info
        string memory path = "deployments/well.json";
        string memory out;
        if (isLocal) {
            out = string.concat(
                "{",
                '"deployer":"',
                vm.toString(deployer),
                '",',
                '"well":"',
                vm.toString(address(well)),
                '",',
                '"wrapper":"',
                vm.toString(wrapperAddr),
                '",',
                '"coordinator":"',
                vm.toString(coordinatorAddr),
                '"',
                "}"
            );
        } else {
            out = string.concat(
                "{",
                '"deployer":"',
                vm.toString(deployer),
                '",',
                '"well":"',
                vm.toString(address(well)),
                '",',
                '"wrapper":"',
                vm.toString(wrapperAddr),
                '"',
                "}"
            );
        }
        vm.writeFile(path, out);

        console2.log("");
        console2.log("=== Deployment Complete ===");
        console2.log("Well:", address(well));
        console2.log("Wrote:", path);
    }
}
