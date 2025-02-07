// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {Web3ite} from "../src/Web3ite.sol";

contract DeployWeb3ite is Script {
    function run() external returns (Web3ite) {
        // 1) private key 세팅
        // forge script 실행 시 --private-key 옵션으로 주는 등
        vm.startBroadcast();

        // 2) 컨트랙트 배포
        Web3ite web3ite = new Web3ite();

        vm.stopBroadcast();

        return web3ite;
    }
}
