// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Counter } from "src/contracts/Counter.sol";
import { Script, console2 as console } from "lib/forge-std/src/Script.sol";

contract DeterministicDeployment is Script {
    address private __CREATE2_DEPLOYER__ = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    bytes32 constant __SALT__ = 0x00000000000000000000000000000000000000000000000000000003868c4fa3;

    function run() public {
        vm.startBroadcast();

        bytes memory creationCode = abi.encodePacked(type(Counter).creationCode);
        // console.logBytes(creationCode);

        address expectedAddress = vm.computeCreate2Address(__SALT__, keccak256(creationCode), __CREATE2_DEPLOYER__);

        console.log("Expected deployment address:", expectedAddress);
        console.log("Using salt:", vm.toString(__SALT__));
        console.log("CREATE2 Deployer:", __CREATE2_DEPLOYER__);

        if (expectedAddress.code.length > 0) {
            console.log("Contract already deployed at:", expectedAddress);
            vm.stopBroadcast();
            return;
        }

        bytes memory deploymentData = abi.encodePacked(__SALT__, creationCode);

        (bool success, bytes memory res) = __CREATE2_DEPLOYER__.call(deploymentData);
        require(address(bytes20(res)) == expectedAddress, "Wrong Addres Delpoyed");

        require(success, "CREATE2 deployment failed");

        console.log("Contract deployed successfully!");
        console.log("Deployed to expected address:", expectedAddress);

        require(expectedAddress.code.length > 0, "No code at deployed address");

        console.log("Deployment completed successfully!");

        vm.stopBroadcast();
    }
}
