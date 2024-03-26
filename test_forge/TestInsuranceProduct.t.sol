// SPDX-License-Identifier: APACHE-2.0
pragma solidity 0.8.20;

import {console} from "forge-std/src/Test.sol";

import {APPLIED, ACTIVE, UNDERWRITTEN, CLOSED} from "gif-next/contracts/types/StateId.sol";
import {Fee, FeeLib} from "gif-next/contracts/types/Fee.sol";
import {IBundle} from "gif-next/contracts/instance/module/IBundle.sol";
import {IComponents} from "gif-next/contracts/instance/module/IComponents.sol";
import {ILifecycle} from "gif-next/contracts/instance/base/ILifecycle.sol";
import {IPolicy} from "gif-next/contracts/instance/module/IPolicy.sol";
import {IRisk} from "gif-next/contracts/instance/module/IRisk.sol";
import {ISetup} from "gif-next/contracts/instance/module/ISetup.sol";
import {NftId, NftIdLib} from "gif-next/contracts/types/NftId.sol";
import {POLICY} from "gif-next/contracts/types/ObjectType.sol";
import {PRODUCT_OWNER_ROLE, DISTRIBUTION_OWNER_ROLE, POOL_OWNER_ROLE} from "gif-next/contracts/types/RoleId.sol";
import {ReferralLib} from "gif-next/contracts/types/Referral.sol";
import {RiskId, RiskIdLib, eqRiskId} from "gif-next/contracts/types/RiskId.sol";
import {Seconds, SecondsLib} from "gif-next/contracts/types/Seconds.sol";
import {TestGifBase} from "gif-next/test_forge/base/TestGifBase.sol";
import {Timestamp, TimestampLib, zeroTimestamp} from "gif-next/contracts/types/Timestamp.sol";
import {UFixedLib} from "gif-next/contracts/types/UFixed.sol";

import {BasicDistribution} from "../contracts/BasicDistribution.sol";
import {BasicPool} from "../contracts/BasicPool.sol";
import {InsuranceProduct} from "../contracts/InsuranceProduct.sol";



contract TestInsuranceProduct is TestGifBase {
    using NftIdLib for NftId;

    Seconds public sec30;

    function setUp() public override {
        super.setUp();
        sec30 = SecondsLib.toSeconds(30);
    }

    function test_InsuranceProduct_underwriteWithPayment() public {
        // GIVEN
        vm.startPrank(registryOwner);
        token.transfer(customer, 1000);
        vm.stopPrank();

        _prepareProduct();  

        vm.startPrank(productOwner);

        Fee memory productFee = FeeLib.toFee(UFixedLib.zero(), 10);
        product.setFees(productFee, FeeLib.zeroFee());

        RiskId riskId = RiskIdLib.toRiskId("42x4711");
        bytes memory data = "bla di blubb";
        InsuranceProduct iproduct = InsuranceProduct(address(product));
        iproduct.createRisk(riskId, data);

        vm.stopPrank();

        vm.startPrank(customer);

        ISetup.ProductSetupInfo memory productSetupInfo = instanceReader.getProductSetupInfo(productNftId);
        token.approve(address(productSetupInfo.tokenHandler), 1000);
        // revert("checkApprove");

        NftId policyNftId = iproduct.createApplication(
            customer,
            riskId,
            1000,
            SecondsLib.toSeconds(30),
            "",
            bundleNftId,
            ReferralLib.zero()
        );
        assertTrue(policyNftId.gtz(), "policyNftId was zero");
        assertEq(chainNft.ownerOf(policyNftId.toInt()), customer, "customer not owner of policyNftId");

        assertTrue(instance.getState(policyNftId.toKey32(POLICY())) == APPLIED(), "state not APPLIED");
        
        vm.stopPrank();

        // WHEN
        vm.startPrank(productOwner);
        iproduct.underwrite(policyNftId, true, TimestampLib.blockTimestamp()); 

        // THEN
        assertTrue(instanceReader.getPolicyState(policyNftId) == ACTIVE(), "policy state not UNDERWRITTEN");

        IBundle.BundleInfo memory bundleInfo = instanceReader.getBundleInfo(bundleNftId);
        assertEq(bundleInfo.lockedAmount.toInt(), 1000, "lockedAmount not 1000");
        assertEq(bundleInfo.feeAmount.toInt(), 10, "feeAmount not 10");
        assertEq(bundleInfo.capitalAmount.toInt(), 10000 + 100 - 10, "capitalAmount not 1100");
        
        IPolicy.PolicyInfo memory policyInfo = instanceReader.getPolicyInfo(policyNftId);
        assertTrue(policyInfo.activatedAt.gtz(), "activatedAt not set");
        assertTrue(policyInfo.expiredAt.gtz(), "expiredAt not set");
        assertTrue(policyInfo.expiredAt.toInt() == policyInfo.activatedAt.addSeconds(sec30).toInt(), "expiredAt not activatedAt + 30");

        assertEq(token.balanceOf(product.getWallet()), 10, "product balance not 10");
        assertEq(token.balanceOf(distribution.getWallet()), 10, "distibution balance not 10");
        assertEq(token.balanceOf(address(customer)), 880, "customer balance not 880");
        assertEq(token.balanceOf(pool.getWallet()), 10100, "pool balance not 10100");

        assertEq(instanceBundleManager.activePolicies(bundleNftId), 1, "expected one active policy");
        assertTrue(instanceBundleManager.getActivePolicy(bundleNftId, 0).eq(policyNftId), "active policy nft id in bundle manager not equal to policy nft id");
    }

    function _prepareProduct() internal {
        vm.startPrank(instanceOwner);
        instanceAccessManager.grantRole(PRODUCT_OWNER_ROLE(), productOwner);
        instanceAccessManager.grantRole(DISTRIBUTION_OWNER_ROLE(), distributionOwner);
        instanceAccessManager.grantRole(POOL_OWNER_ROLE(), poolOwner);
        vm.stopPrank();

        vm.startPrank(distributionOwner);
        distribution = new BasicDistribution(
            "BasicDistribution",
            address(registry),
            instanceNftId,
            address(token),
            FeeLib.zeroFee(),
            FeeLib.zeroFee(),
            distributionOwner
        );
        distributionNftId = distributionService.register(address(distribution));
        vm.stopPrank();

        vm.startPrank(poolOwner);
        pool = new BasicPool(
            "BasicPool",
            address(registry),
            instanceNftId,
            address(token),
            false,
            poolOwner
        );
        poolNftId = poolService.register(address(pool));
        vm.stopPrank();

        vm.startPrank(productOwner);
        product = new InsuranceProduct(
            "InsuranceProduct",
            address(registry),
            instanceNftId,
            address(token),
            false,
            address(pool), 
            address(distribution),
            FeeLib.zeroFee(),
            FeeLib.zeroFee(),
            productOwner
        );
        
        productNftId = productService.register(address(product));
        vm.stopPrank();

        vm.startPrank(distributionOwner);
        Fee memory distributionFee = FeeLib.toFee(UFixedLib.zero(), 10);
        Fee memory minDistributionOwnerFee = FeeLib.toFee(UFixedLib.zero(), 10);
        distribution.setFees(minDistributionOwnerFee, distributionFee);
        vm.stopPrank();

        vm.startPrank(poolOwner);
        Fee memory poolFee = FeeLib.toFee(UFixedLib.zero(), 10);
        pool.setFees(poolFee, FeeLib.zeroFee(), FeeLib.zeroFee());
        vm.stopPrank();

        vm.startPrank(registryOwner);
        token.transfer(investor, 10000);
        vm.stopPrank();

        vm.startPrank(investor);
        IComponents.ComponentInfo memory componentInfo = instanceReader.getComponentInfo(poolNftId);
        token.approve(address(componentInfo.tokenHandler), 10000);

        Fee memory bundleFee = FeeLib.toFee(UFixedLib.zero(), 10);
        BasicPool bpool = BasicPool(address(pool));
        bundleNftId = bpool.createBundle(
            bundleFee, 
            10000, 
            SecondsLib.toSeconds(604800), 
            ""
        );
        vm.stopPrank();
    }

}
