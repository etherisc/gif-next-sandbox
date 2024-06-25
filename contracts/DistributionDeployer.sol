// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {MyDistribution} from "./MyDistribution.sol";
import {NftId} from "gif-next/contracts/type/NftId.sol";
import {BasicDistributionAuthorization} from "gif-next/contracts/distribution/BasicDistributionAuthorization.sol";
import {IAuthorization} from "gif-next/contracts/authorization/IAuthorization.sol";

library DistributionDeployer {

    function deployDistribution(address registry,
            NftId instanceNftId,
            address owner,
            string memory name,
            IAuthorization auth,
            address token) public returns (MyDistribution) {
        return new MyDistribution(
            registry,
            instanceNftId,
            auth,
            owner,
            name,
            token
        );
    }
}
