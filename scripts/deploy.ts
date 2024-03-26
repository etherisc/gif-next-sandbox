import { AddressLike, Signer, resolveAddress } from "ethers";
import { DistributionService__factory, PoolService__factory, ProductService__factory, Registry__factory, TokenRegistry__factory } from "../lib/gif-next/typechain-types";
import { Distribution, IInstance__factory, InstanceAccessManager__factory, Pool, Product } from "../typechain-types";
import { getNamedAccounts } from "./libs/accounts";
import { deployContract } from "./libs/deployment";
import { executeTx, getFieldFromTxRcptLogs } from "./libs/transaction";
import { logger } from "./logger";
import { DISTRIBUTION_OWNER_ROLE, OBJECT_TYPE_DISTRIBUTION, OBJECT_TYPE_POOL, OBJECT_TYPE_PRODUCT, POOL_OWNER_ROLE, PRODUCT_OWNER_ROLE } from "./libs/gif_constants";

async function main() {
    logger.info("deploying components ...");
    const { protocolOwner, instanceOwner, distributionOwner, poolOwner, productOwner } = await getNamedAccounts();

    const amountLibAddress = process.env.AMOUNTLIB_ADDRESS;
    const feeLibAddress = process.env.FEELIB_ADDRESS;
    const nftIdLibAddress = process.env.NFTIDLIB_ADDRESS;
    const referralLibAddress = process.env.REFERRALLIB_ADDRESS;
    const roleIdLibAddress = process.env.ROLEIDLIB_ADDRESS;
    const ufixedLibAddress = process.env.UFIXEDLIB_ADDRESS;
    
    const instanceNftId = process.env.INSTANCE_NFTID;
    const instanceAddress = process.env.INSTANCE_ADDRESS;
    
    const instance = IInstance__factory.connect(instanceAddress!, instanceOwner);
    const instanceAccessManagerAddress = await instance.getInstanceAccessManager();
    const registryAddress = await instance.getRegistry();
    const instanceAccessManager = InstanceAccessManager__factory.connect(instanceAccessManagerAddress, instanceOwner);
    await executeTx(() => instanceAccessManager.grantRole(DISTRIBUTION_OWNER_ROLE, distributionOwner));
    console.log(`Distribution owner role granted to ${distributionOwner} at ${instanceAccessManagerAddress}`);
    await executeTx(() => instanceAccessManager.grantRole(POOL_OWNER_ROLE, poolOwner));
    console.log(`Pool owner role granted to ${poolOwner} at ${instanceAccessManagerAddress}`);
    await executeTx(() => instanceAccessManager.grantRole(PRODUCT_OWNER_ROLE, productOwner));
    console.log(`Product owner role granted to ${productOwner} at ${instanceAccessManagerAddress}`);
    
    const { address: usdcMockAddress } = await deployContract(
        "UsdcMock",
        protocolOwner);

    const { distributionAddress } = await deployAndRegisterDistribution(
        distributionOwner,
        instanceNftId!,
        usdcMockAddress,
        registryAddress!,
        nftIdLibAddress!,
        referralLibAddress!
    );
    const { poolAddress } = await deployAndRegisterPool(
        poolOwner,
        instanceNftId!,
        usdcMockAddress,
        registryAddress!,
        nftIdLibAddress!,
        amountLibAddress!,
        feeLibAddress!,
        roleIdLibAddress!,
        ufixedLibAddress!,
    );
    await deployAndRegisterProduct(
        productOwner,
        instanceNftId!,
        usdcMockAddress,
        registryAddress!,
        poolAddress,
        distributionAddress,
        nftIdLibAddress!,
    );
    
    // workaround to get script to stop
    process.exit(0);
}

async function deployAndRegisterDistribution(
    distributionOwner: Signer,
    instanceNftId: string, 
    usdcMockAddress: AddressLike,
    registryAddress: AddressLike, 
    nftIdLibAddress: AddressLike, 
    referralLibAddress: AddressLike, 
): Promise<{ distribution: Distribution, distributionNftId: string, distributionAddress: AddressLike }>  {
    const distName = "BasicDistribution-" + Math.random().toString(16).substring(7);
    const fee = {
        fractionalFee: 0,
        fixedFee: 0,
    };
    const { address: distAddress, contract: dist } = await deployContract(
        "BasicDistribution",
        distributionOwner,
        [
            distName,
            registryAddress,
            instanceNftId,
            usdcMockAddress,
            fee,
            fee,
            distributionOwner
        ],
        {
            libraries: {
                NftIdLib: nftIdLibAddress,
                ReferralLib: referralLibAddress,
            }
        });

    const registry = Registry__factory.connect(await resolveAddress(registryAddress), distributionOwner);
    const distributuonServiceAddress = await registry.getServiceAddress(OBJECT_TYPE_DISTRIBUTION, 3);
    const distributionService = DistributionService__factory.connect(distributuonServiceAddress, distributionOwner);

    console.log(`Registering distribution at ${distAddress} ...`);
    const rcpt = await executeTx(() => distributionService.register(distAddress));
    const distNftId = getFieldFromTxRcptLogs(rcpt!, registry.interface, "LogRegistration", "nftId");
    console.log(`Distribution ${distName} registered at ${distAddress} with ${distNftId}`);
    return {
        distribution: dist as Distribution,
        distributionNftId: distNftId as string,
        distributionAddress: distAddress,
    };
}

async function deployAndRegisterPool(
    poolOwner: Signer,
    instanceNftId: string, 
    usdcMockAddress: AddressLike,
    registryAddress: AddressLike, 
    nftIdLibAddress: AddressLike, 
    amountLibAddress: AddressLike,
    feeLibAddress: AddressLike,
    roleIdLibAddress: AddressLike,
    ufixedLibAddress: AddressLike,
): Promise<{ pool: Pool, poolNftId: string, poolAddress: AddressLike }> {
    const poolName = "BasicPool-" + Math.random().toString(16).substring(7);
    const { address: poolAddress, contract: pool } = await deployContract(
        "BasicPool",
        poolOwner,
        [
            poolName,
            registryAddress,
            instanceNftId,
            usdcMockAddress,
            false,
            poolOwner
        ],
        {
            libraries: {
                NftIdLib: nftIdLibAddress,
                AmountLib: amountLibAddress,
                FeeLib: feeLibAddress,
                RoleIdLib: roleIdLibAddress,
                UFixedLib: ufixedLibAddress,
            }
        });

    const registry = Registry__factory.connect(await resolveAddress(registryAddress), poolOwner);
    const poolServiceAddress = await registry.getServiceAddress(OBJECT_TYPE_POOL, 3);
    const poolService = PoolService__factory.connect(poolServiceAddress, poolOwner);

    console.log(`Registering pool at ${poolAddress} ...`);
    const rcpt = await executeTx(() => poolService.register(poolAddress));
    const poolNftId = getFieldFromTxRcptLogs(rcpt!, registry.interface, "LogRegistration", "nftId");
    console.log(`Distribution ${poolName} registered at ${poolAddress} with ${poolNftId}`);
    return {
        pool: pool as Pool,
        poolNftId: poolNftId as string,
        poolAddress,
    };
}

async function deployAndRegisterProduct(
    productOwner: Signer,
    instanceNftId: string, 
    usdcMockAddress: AddressLike,
    registryAddress: AddressLike, 
    poolAddress: AddressLike,
    distributionAddress: AddressLike,
    nftIdLibAddress: AddressLike, 
): Promise<{ product: Product, productNftId: string, productAddress: AddressLike }> {
    const productName = "InsuranceProduct-" + Math.random().toString(16).substring(7);
    const fee = {
        fractionalFee: 0,
        fixedFee: 0,
    };
    const { address: productAddress, contract: product } = await deployContract(
        "InsuranceProduct",
        productOwner,
        [
            productName,
            registryAddress,
            instanceNftId,
            usdcMockAddress,
            false,
            poolAddress,
            distributionAddress,
            fee,
            fee,
            productOwner
        ],
        {
            libraries: {
                NftIdLib: nftIdLibAddress,
            }
        });

    const registry = Registry__factory.connect(await resolveAddress(registryAddress), productOwner);
    const productServiceAddress = await registry.getServiceAddress(OBJECT_TYPE_PRODUCT, 3);
    const productService = ProductService__factory.connect(productServiceAddress, productOwner);

    console.log(`Registering product at ${productAddress} ...`);
    const rcpt = await executeTx(() => productService.register(productAddress));
    const productNftId = getFieldFromTxRcptLogs(rcpt!, registry.interface, "LogRegistration", "nftId");
    console.log(`Product ${productName} registered at ${productAddress} with ${productNftId}`);
    return {
        product: product as Product,
        productNftId: productNftId as string,
        productAddress,
    };
}


main().catch((error) => {
    logger.error(error.stack);
    process.exit(1);
});