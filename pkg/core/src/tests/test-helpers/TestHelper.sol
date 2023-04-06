// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Internal references
import { Divider, TokenHandler } from "../../Divider.sol";
import { BaseFactory, ChainlinkOracleLike } from "../../adapters/abstract/factories/BaseFactory.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { IPriceFeed } from "../../adapters/abstract/IPriceFeed.sol";
import { PoolManager } from "@sense-finance/v1-fuse/PoolManager.sol";
import { Token } from "../../tokens/Token.sol";
import { Periphery } from "../../Periphery.sol";
import { MockToken, MockNonERC20Token } from "./mocks/MockToken.sol";
import { MockTarget, MockNonERC20Target } from "./mocks/MockTarget.sol";
import { MockAdapter, MockCropAdapter, Mock4626CropAdapter } from "./mocks/MockAdapter.sol";
import { MockERC4626 } from "./mocks/MockERC4626.sol";
import { ERC4626Adapter } from "../../adapters/abstract/erc4626/ERC4626Adapter.sol";
import { ERC4626Factory } from "../../adapters/abstract/factories/ERC4626Factory.sol";
import { ERC4626CropsFactory } from "../../adapters/abstract/factories/ERC4626CropsFactory.sol";
import { ERC4626CropFactory } from "../../adapters/abstract/factories/ERC4626CropFactory.sol";
import { MockFactory, MockCropFactory, MockCropsFactory, Mock4626CropsFactory } from "./mocks/MockFactory.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
import { Constants } from "./Constants.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

// Space & Balanacer V2 mock
import { MockSpaceFactory, MockBalancerVault } from "./mocks/MockSpace.sol";

// Fuse & compound mocks
import { MockComptroller } from "./mocks/fuse/MockComptroller.sol";
import { MockFuseDirectory } from "./mocks/fuse/MockFuseDirectory.sol";
import { MockOracle } from "./mocks/fuse/MockOracle.sol";

// Permit2
import { Permit2Helper } from "./Permit2Helper.sol";

import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";

import { DateTimeFull } from "./DateTimeFull.sol";
import { FixedMath } from "../../external/FixedMath.sol";

interface MockTargetLike {
    // mintable erc20
    function decimals() external returns (uint256);

    function totalSupply() external returns (uint256);

    function balanceOf(address usr) external returns (uint256);

    function mint(address account, uint256 amount) external;

    function approve(address account, uint256 amount) external;

    function transfer(address to, uint256 amount) external returns (bool);

    // target
    function underlying() external returns (address);

    // erc4626
    function asset() external returns (address);

    function totalAssets() external returns (uint256);

    function previewDeposit(uint256 assets) external returns (uint256);

    function previewMint(uint256 shares) external returns (uint256);

    function mint(uint256 shares, address receiver) external;

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
}

interface CTokenInterface {
    function mint(uint256 mintAmount) external returns (uint256);
}

contract TestHelper is Test, Permit2Helper {
    using SafeTransferLib for ERC20;
    using FixedMath for uint256;
    using FixedMath for uint64;

    MockCropAdapter internal adapter;
    MockToken internal stake;
    MockToken internal underlying;
    MockTargetLike internal target;
    MockToken internal reward;
    MockCropFactory internal factory;
    MockOracle internal masterOracle;

    // PoolManager internal poolManager;
    Divider internal divider;
    TokenHandler internal tokenHandler;
    Periphery internal periphery;

    address internal alice = address(this); // alice is the default user
    uint256 internal bobPrivKey = _randomUint256();
    address internal bob = vm.addr(bobPrivKey);
    uint256 internal jimPrivKey = _randomUint256();
    address internal jim = vm.addr(jimPrivKey);

    // balancer/space
    MockSpaceFactory internal spaceFactory;
    MockBalancerVault internal balancerVault;

    // fuse & compound
    MockComptroller internal comptroller;
    MockFuseDirectory internal fuseDirectory;

    // default adapter params
    BaseAdapter.AdapterParams public DEFAULT_ADAPTER_PARAMS;

    uint256 internal GROWTH_PER_SECOND = 792744799594; // 25% APY
    uint8 public MODE = 0;
    address public ORACLE = address(123);
    uint64 public ISSUANCE_FEE = 0.05e18;
    uint256 public STAKE_SIZE = 1e18;
    uint256 public MIN_MATURITY = 2 weeks;
    uint256 public MAX_MATURITY = 14 weeks;
    uint16 public DEFAULT_LEVEL = 31;
    uint16 public DEFAULT_TILT = 0;
    uint256 public DEFAULT_GUARD = 100000 * 1e18; // guard in target terms
    uint256 public SPONSOR_WINDOW;
    uint256 public SETTLEMENT_WINDOW;
    uint256 public SCALING_FACTOR;

    // target type
    bool internal is4626Target;
    uint256 public AMT = 2000; // Amount of tokens to initialise the user with
    uint256 public MIN_TARGET = 1e4; // test with a target with less than 4 decimals will fail
    uint256 public MAX_TARGET;

    // non ERC20 compliant
    bool internal nonERC20Target;
    bool internal nonERC20Underlying;
    bool internal nonERC20Stake;

    // decimals
    uint8 internal tDecimals;
    uint8 internal uDecimals;
    uint8 internal sDecimals;
    uint8 internal rDecimals;

    function setUp() public virtual {
        vm.warp(1630454400);
        // 01-09-21 00:00 UTC

        // read env vars (or set defaults if none)
        setEnv();
        // Create target, underlying, stake & reward tokens
        stake = MockToken(deployMockStake("Stake Token", "ST", sDecimals));
        underlying = MockToken(deployMockUnderlying("Dai Token", "DAI", uDecimals));

        // To avoid precision errors when using `assertApproxEqAbs` (specially on the crop tests)
        // we set the reward token decimals to the same as the target decimals
        rDecimals = tDecimals;
        reward = new MockToken("Reward Token", "RT", rDecimals);

        // Log target setup
        target = MockTargetLike(deployMockTarget(address(underlying), "Compound Dai", "cDAI", tDecimals));

        SCALING_FACTOR = 10**(tDecimals > uDecimals ? tDecimals - uDecimals : uDecimals - tDecimals);

        GROWTH_PER_SECOND = convertToBase(GROWTH_PER_SECOND, target.decimals());

        // divider
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        tokenHandler.init(address(divider));

        SPONSOR_WINDOW = divider.SPONSOR_WINDOW();
        SETTLEMENT_WINDOW = divider.SETTLEMENT_WINDOW();

        // balancer/space mocks
        balancerVault = new MockBalancerVault();
        spaceFactory = new MockSpaceFactory(address(balancerVault), address(divider));
        balancerVault.setSpaceFactory(address(spaceFactory));

        // fuse & comp mocks
        comptroller = new MockComptroller();
        fuseDirectory = new MockFuseDirectory(address(comptroller));
        masterOracle = new MockOracle();

        // pool manager
        // poolManager = new PoolManager(
        //     address(fuseDirectory),
        //     address(comptroller),
        //     address(1),
        //     address(divider),
        //     address(masterOracle) // oracle impl
        // );
        // poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(1));
        // PoolManager.AssetParams memory params = PoolManager.AssetParams({
        //     irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
        //     reserveFactor: 0.1 ether,
        //     collateralFactor: 0.5 ether
        // });
        // poolManager.setParams("TARGET_PARAMS", params);

        // periphery
        periphery = new Periphery(
            address(divider),
            address(spaceFactory),
            address(balancerVault),
            address(permit2),
            address(0)
        );
        divider.setPeriphery(address(periphery));
        // poolManager.setIsTrusted(address(periphery), true);

        // scale stake size to stake decimals
        STAKE_SIZE = STAKE_SIZE.fdiv(1e18, sDecimals);

        // adapter, target wrapper & factory
        DEFAULT_ADAPTER_PARAMS = BaseAdapter.AdapterParams({
            oracle: ORACLE,
            stake: address(stake),
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0,
            level: DEFAULT_LEVEL
        });

        // mock all calls to ETH_USD_PRICEFEED (Chainlink oracle)
        bytes memory returnData = abi.encode(
            1,
            int256(Constants.DEFAULT_CHAINLINK_ETH_PRICE),
            block.timestamp,
            block.timestamp,
            1
        ); // return data
        ChainlinkOracleLike oracle = ChainlinkOracleLike(AddressBook.ETH_USD_PRICEFEED);
        vm.mockCall(address(address(oracle)), abi.encodeWithSelector(oracle.latestRoundData.selector), returnData);

        // mock all calls to oracle price
        returnData = abi.encode(1e18); // return data
        vm.mockCall(
            address(ORACLE),
            abi.encodeWithSelector(IPriceFeed(ORACLE).price.selector, address(underlying)),
            returnData
        );

        // factories
        factory = MockCropFactory(deployCropFactory(address(target)));

        // Prepare data
        bytes memory data = abi.encode(address(reward));

        // Deploy adapter
        address a = periphery.deployAdapter(address(factory), address(target), data); // deploy & onboard target through Periphery
        adapter = MockCropAdapter(a);

        // Init scale
        adapter.scale();

        // users
        MAX_TARGET = AMT * 10**target.decimals();
        vm.label(alice, "Alice");
        initUser(alice, target, AMT);
        vm.label(bob, "Bob");
        initUser(bob, target, AMT);
        vm.label(jim, "Jim");
        initUser(jim, target, AMT);
    }

    function initUser(
        address usr,
        MockTargetLike target,
        uint256 amt
    ) public {
        vm.startPrank(usr);

        // divider approvals
        ERC20(address(underlying)).safeApprove(address(divider), type(uint256).max);
        ERC20(address(target)).safeApprove(address(divider), type(uint256).max);

        // permit2 approvals (used on `Periphery`)
        ERC20(address(underlying)).safeApprove(address(permit2), type(uint256).max);
        ERC20(address(target)).safeApprove(address(permit2), type(uint256).max);
        ERC20(address(stake)).safeApprove(address(permit2), type(uint256).max);

        // amounts to mint
        uint256 underlyingAmt = amt * 10**uDecimals;
        uint256 targetAmt = amt * 10**tDecimals;
        uint256 stakeAmt = amt * 10**sDecimals;

        // minting
        underlying.mint(usr, underlyingAmt);
        stake.mint(usr, stakeAmt);

        // if 4626 we need to deposit instead of directly minting target
        if (is4626Target) {
            uint256 assets = target.previewMint(targetAmt);
            underlying.mint(usr, assets);
            if (nonERC20Target) {
                MockNonERC20Token(address(underlying)).approve(address(target), type(uint256).max);
            } else {
                underlying.approve(address(target), type(uint256).max);
            }
            target.mint(targetAmt, usr);
        } else {
            target.mint(usr, targetAmt);
        }

        vm.stopPrank();
    }

    // ---- liquidity provision ---- //

    function addLiquidityToBalancerVault(
        address adapter,
        uint256 maturity,
        uint256 tBal
    ) public {
        return _addLiquidityToBalancerVault(adapter, maturity, tBal);
    }

    function addLiquidityToBalancerVault(uint256 maturity, uint256 tBal) public {
        return _addLiquidityToBalancerVault(address(adapter), maturity, tBal);
    }

    function _addLiquidityToBalancerVault(
        address adapter,
        uint256 maturity,
        uint256 tBal
    ) internal {
        MockTargetLike target = MockTargetLike(MockAdapter(adapter).target());
        MockToken underlying = MockToken(!is4626Target ? target.underlying() : target.asset());

        if (!is4626Target) {
            // mint target and transfer half to the vault and half to user
            target.mint(address(balancerVault), tBal / 2);
            target.mint(address(this), tBal / 2);
        } else {
            // mint enough underlying to mint desired target `tBal`
            uint256 uBal = target.previewMint(tBal);

            // we mint target using double the `uBal` so we then use half of the minted target
            // for issuing PTs and half for adding it to the vault
            underlying.mint(address(this), uBal * 2);

            // approve erc4626 contract to pull underlying to be able to mint target
            underlying.approve(address(target), type(uint256).max);

            // mint target and transfer half to the vault and half to user
            target.mint(tBal / 2, address(balancerVault));
            target.mint(tBal / 2, address(this));
        }

        // issue PTs using half the tBal and transfer it to the vault
        ERC20(address(target)).safeApprove(address(divider), tBal / 2);
        uint256 issued = divider.issue(address(adapter), maturity, tBal / 2);
        MockToken(divider.pt(address(adapter), maturity)).transfer(address(balancerVault), issued);
    }

    // ---- deployers ---- //

    function deployERC4626Factory(address _target) public returns (address someFactory) {
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: address(stake),
            oracle: ORACLE,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0,
            guard: DEFAULT_GUARD
        });
        someFactory = address(
            new ERC4626Factory(address(divider), Constants.RESTRICTED_ADMIN, Constants.REWARDS_RECIPIENT, factoryParams)
        );
        MockFactory(someFactory).supportTarget(_target, true);
        divider.setIsTrusted(someFactory, true);
        periphery.setFactory(someFactory, true);
    }

    function deployERC4626CropsFactory(address _target) public returns (address someFactory) {
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: address(stake),
            oracle: ORACLE,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0,
            guard: DEFAULT_GUARD
        });
        someFactory = address(
            new ERC4626CropsFactory(
                address(divider),
                Constants.RESTRICTED_ADMIN,
                Constants.REWARDS_RECIPIENT,
                factoryParams
            )
        );
        MockFactory(someFactory).supportTarget(_target, true);
        divider.setIsTrusted(someFactory, true);
        periphery.setFactory(someFactory, true);
    }

    /// Deploys either an ERC4626Factory or a MockFactory (no crops involved).
    function deployFactory(address _target) public returns (address someFactory) {
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: address(stake),
            oracle: ORACLE,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0,
            guard: DEFAULT_GUARD
        });
        if (is4626Target) {
            someFactory = address(
                new ERC4626Factory(
                    address(divider),
                    Constants.RESTRICTED_ADMIN,
                    Constants.REWARDS_RECIPIENT,
                    factoryParams
                )
            );
        } else {
            someFactory = address(
                new MockFactory(
                    address(divider),
                    Constants.RESTRICTED_ADMIN,
                    Constants.REWARDS_RECIPIENT,
                    factoryParams
                )
            );
        }
        MockFactory(someFactory).supportTarget(_target, true);
        divider.setIsTrusted(someFactory, true);
        periphery.setFactory(someFactory, true);
    }

    function deployCropsFactory(address _target) public returns (address someFactory) {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(reward);
        return deployCropsFactory(_target, rewardTokens, true);
    }

    function deployCropFactory(address _target) public returns (address someFactory) {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(reward);
        return deployCropsFactory(_target, rewardTokens, false);
    }

    /// Deploys either a MockCropFactory, a MockCropsFactory or a ERC4626CropsFactory.
    function deployCropsFactory(
        address _target,
        address[] memory _rewardTokens,
        bool crops
    ) public returns (address someFactory) {
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: address(stake),
            oracle: ORACLE,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0,
            guard: DEFAULT_GUARD
        });

        if (is4626Target) {
            if (crops) {
                someFactory = address(
                    new ERC4626CropsFactory(
                        address(divider),
                        Constants.RESTRICTED_ADMIN,
                        Constants.REWARDS_RECIPIENT,
                        factoryParams
                    )
                );
            } else {
                someFactory = address(
                    new ERC4626CropFactory(
                        address(divider),
                        Constants.RESTRICTED_ADMIN,
                        Constants.REWARDS_RECIPIENT,
                        factoryParams
                    )
                );
            }
        } else {
            if (crops) {
                someFactory = address(
                    new MockCropsFactory(
                        address(divider),
                        Constants.RESTRICTED_ADMIN,
                        Constants.REWARDS_RECIPIENT,
                        factoryParams,
                        _rewardTokens
                    )
                );
            } else {
                someFactory = address(
                    new MockCropFactory(
                        address(divider),
                        Constants.RESTRICTED_ADMIN,
                        Constants.REWARDS_RECIPIENT,
                        factoryParams,
                        _rewardTokens[0]
                    )
                );
            }
        }
        MockFactory(someFactory).supportTarget(_target, true);
        divider.setIsTrusted(someFactory, true);
        periphery.setFactory(someFactory, true);
    }

    function deployMockTarget(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) internal returns (address _target) {
        if (is4626Target) {
            _target = address(new MockERC4626(ERC20(_underlying), _name, _symbol, _decimals));
        } else if (nonERC20Target) {
            _target = address(new MockNonERC20Target(_underlying, _name, _symbol, _decimals));
        } else {
            _target = address(new MockTarget(_underlying, _name, _symbol, _decimals));
        }
    }

    function deployMockUnderlying(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) internal returns (address _underlying) {
        if (nonERC20Underlying) {
            _underlying = address(new MockNonERC20Token(_name, _symbol, _decimals));
        } else {
            _underlying = address(new MockToken(_name, _symbol, _decimals));
        }
    }

    function deployMockStake(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) internal returns (address _stake) {
        if (nonERC20Stake) {
            _stake = address(new MockNonERC20Token(_name, _symbol, _decimals));
        } else {
            _stake = address(new MockToken(_name, _symbol, _decimals));
        }
    }

    // Deploys either a mock crop adapter or a 4626 mock crop adapter
    function deployMockAdapter(
        address _divider,
        address _target,
        address _reward
    ) internal returns (address _adapter) {
        if (!is4626Target) {
            _adapter = address(
                new MockCropAdapter(
                    address(_divider),
                    address(_target),
                    target.underlying(),
                    Constants.REWARDS_RECIPIENT,
                    ISSUANCE_FEE,
                    DEFAULT_ADAPTER_PARAMS,
                    address(_reward)
                )
            );
        } else {
            _adapter = address(
                new Mock4626CropAdapter(
                    address(_divider),
                    address(_target),
                    target.asset(),
                    Constants.REWARDS_RECIPIENT,
                    ISSUANCE_FEE,
                    DEFAULT_ADAPTER_PARAMS,
                    address(_reward)
                )
            );
        }
    }

    // ---- utils ---- //

    function getValidMaturity(uint256 year, uint256 month) public view returns (uint256 maturity) {
        maturity = DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0);
        if (maturity < block.timestamp + 2 weeks) revert("InvalidMaturityOffsets");
    }

    function convertToBase(uint256 amount, uint256 decimals) internal pure returns (uint256) {
        if (decimals != 18) {
            amount = decimals > 18 ? amount * 10**(decimals - 18) : amount / 10**(18 - decimals);
        }
        return amount;
    }

    function calculateAmountToIssue(uint256 tBal) public returns (uint256 toIssue) {
        toIssue = tBal.fmul(adapter.scale());
    }

    // for MockAdapter, as scale is a function of time, we just move to some blocks in the future
    // for the ERC4626, we mint some underlying
    function increaseScale(address t) internal {
        if (!is4626Target) {
            vm.warp(block.timestamp + 1 days);
        } else {
            MockERC4626(t).asset();
            MockToken underlying = MockToken(address(MockERC4626(t).asset()));
            underlying.mint(t, underlying.balanceOf(t));
        }
    }

    /// @notice Tries to read env vars and/or sets defaut value if not exists
    function setEnv() internal {
        try vm.envUint("UNDERLYING_DECIMALS") returns (uint256 val) {
            uDecimals = uint8(val);
        } catch {
            uDecimals = uint8(18);
        }

        try vm.envUint("TARGET_DECIMALS") returns (uint256 val) {
            tDecimals = uint8(val);
        } catch {
            tDecimals = uint8(18);
        }

        try vm.envUint("STAKE_DECIMALS") returns (uint256 val) {
            sDecimals = uint8(val);
        } catch {
            sDecimals = uint8(18);
        }

        if (!is4626Target) {
            try vm.envBool("ERC4626_TARGET") returns (bool val) {
                is4626Target = val;
            } catch {}
        }

        if (!nonERC20Target) {
            try vm.envBool("NON_ERC20_TARGET") returns (bool val) {
                nonERC20Target = val;
            } catch {}
        }
        if (!nonERC20Underlying) {
            try vm.envBool("NON_ERC20_UNDERLYING") returns (bool val) {
                nonERC20Underlying = val;
            } catch {}
        }

        if (!nonERC20Stake) {
            try vm.envBool("NON_ERC20_STAKE") returns (bool val) {
                nonERC20Stake = val;
            } catch {}
        }
    }

    function assertApproxEqAbs(uint256 a, uint256 b) public virtual {
        assertApproxEqAbs(a, b, 100);
    }

    function _getQuote(address fromToken, address toToken) public returns (Periphery.SwapQuote memory quote) {
        if (fromToken == address(0)) {
            quote.buyToken = ERC20(toToken);
        } else {
            quote.sellToken = ERC20(fromToken);
        }
        if (fromToken == address(stake)) {
            quote.amount = STAKE_SIZE;
        }
    }
}
