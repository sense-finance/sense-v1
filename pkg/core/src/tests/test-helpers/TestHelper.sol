// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { Divider, TokenHandler } from "../../Divider.sol";
import { BaseFactory } from "../../adapters/BaseFactory.sol";
import { BaseAdapter } from "../../adapters/BaseAdapter.sol";
import { PoolManager } from "@sense-finance/v1-fuse/src/PoolManager.sol";
import { Token } from "../../tokens/Token.sol";
import { Periphery } from "../../Periphery.sol";
import { MockToken } from "./mocks/MockToken.sol";
import { MockTarget } from "./mocks/MockTarget.sol";
import { MockAdapter, Mock4626Adapter } from "./mocks/MockAdapter.sol";
import { MockERC4626 } from "@rari-capital/solmate/src/test/utils/mocks/MockERC4626.sol";
import { ERC4626Adapter } from "../../adapters/ERC4626Adapter.sol";
import { MockFactory, MockCropsFactory } from "./mocks/MockFactory.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";

// Space & Balanacer V2 mock
import { MockSpaceFactory, MockBalancerVault } from "./mocks/MockSpace.sol";

// Fuse & compound mocks
import { MockComptroller } from "./mocks/fuse/MockComptroller.sol";
import { MockFuseDirectory } from "./mocks/fuse/MockFuseDirectory.sol";
import { MockOracle } from "./mocks/fuse/MockOracle.sol";

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { DSTest } from "./test.sol";
import { Hevm } from "./Hevm.sol";
import { DateTimeFull } from "./DateTimeFull.sol";
import { User } from "./User.sol";
import { FixedMath } from "../../external/FixedMath.sol";

interface MockTargetLike {
    // mintable erc20
    function decimals() external returns (uint256);

    function totalSupply() external returns (uint256);

    function balanceOf(address usr) external returns (uint256);

    function mint(address account, uint256 amount) external;

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

contract TestHelper is DSTest {
    using FixedMath for uint256;

    MockAdapter internal adapter;
    MockToken internal stake;
    MockToken internal underlying;
    MockTargetLike internal target;
    MockToken internal reward;
    MockFactory internal factory;
    MockOracle internal masterOracle;

    PoolManager internal poolManager;
    Divider internal divider;
    TokenHandler internal tokenHandler;
    Periphery internal periphery;

    User internal alice;
    User internal bob;
    User internal jim;
    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    // balancer/space
    MockSpaceFactory internal spaceFactory;
    MockBalancerVault internal balancerVault;

    // fuse & compound
    MockComptroller internal comptroller;
    MockFuseDirectory internal fuseDirectory;

    // default adapter params
    BaseAdapter.AdapterParams public DEFAULT_ADAPTER_PARAMS;

    uint256 internal GROWTH_PER_SECOND = 792744799594; // 25% APY
    uint16 public MODE = 0;
    address public ORACLE = address(123);
    uint64 public ISSUANCE_FEE = 0.05e18;
    uint256 public STAKE_SIZE = 1e18;
    uint256 public MIN_MATURITY = 2 weeks;
    uint256 public MAX_MATURITY = 14 weeks;
    uint16 public DEFAULT_LEVEL = 31;
    uint16 public DEFAULT_TILT = 0;
    uint256 public SPONSOR_WINDOW;
    uint256 public SETTLEMENT_WINDOW;
    uint256 public SCALING_FACTOR;

    // target type
    bool internal is4626;
    uint256 public MAX_TARGET = type(uint128).max / 3; // 3 is the amount of users we create

    // decimals
    uint8 internal mockUnderlyingDecimals;
    uint8 internal mockTargetDecimals;

    function setUp() public virtual {
        hevm.warp(1630454400);
        // 01-09-21 00:00 UTC
        uint8 baseDecimals = 18;

        // Get Target/Underlying decimal number from the environment
        string[] memory inputs = new string[](2);
        inputs[0] = "just";
        inputs[1] = "_forge_mock_underlying_decimals";
        mockUnderlyingDecimals = uint8(abi.decode(hevm.ffi(inputs), (uint256)));

        inputs[1] = "_forge_mock_target_decimals";
        mockTargetDecimals = uint8(abi.decode(hevm.ffi(inputs), (uint256)));

        inputs[1] = "_forge_mock_4626_target";
        is4626 = uint8(abi.decode(hevm.ffi(inputs), (uint256))) == 0 ? false : true;

        // Create target, underlying, stake & reward tokens
        stake = new MockToken("Stake Token", "ST", baseDecimals);
        underlying = new MockToken("Dai Token", "DAI", mockUnderlyingDecimals);
        reward = new MockToken("Reward Token", "RT", baseDecimals);

        // Log target setup
        if (is4626) {
            target = MockTargetLike(deployMockTarget(address(underlying), "Compound Dai", "cDAI", mockTargetDecimals));
            emit log("Running tests with a 4626 mock target");
        } else {
            target = MockTargetLike(deployMockTarget(address(underlying), "Compound Dai", "cDAI", mockTargetDecimals));
            emit log("Running tests with a non-4626 mock target");
        }

        // Log decimals setup
        emit log_named_uint(
            "Running tests with the mock Underlying token configured with the following number of decimals",
            uint256(mockUnderlyingDecimals)
        );
        emit log_named_uint(
            "Running tests with the mock Target token configured with the following number of decimals",
            uint256(mockTargetDecimals)
        );

        SCALING_FACTOR =
            10 **
                (
                    mockTargetDecimals > mockUnderlyingDecimals
                        ? mockTargetDecimals - mockUnderlyingDecimals
                        : mockUnderlyingDecimals - mockTargetDecimals
                );

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

        // fuse & comp mocks
        comptroller = new MockComptroller();
        fuseDirectory = new MockFuseDirectory(address(comptroller));
        masterOracle = new MockOracle();

        // pool manager
        poolManager = new PoolManager(
            address(fuseDirectory),
            address(comptroller),
            address(1),
            address(divider),
            address(masterOracle) // oracle impl
        );
        poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(1));
        PoolManager.AssetParams memory params = PoolManager.AssetParams({
            irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            reserveFactor: 0.1 ether,
            collateralFactor: 0.5 ether
        });
        poolManager.setParams("TARGET_PARAMS", params);

        // periphery
        periphery = new Periphery(
            address(divider),
            address(poolManager),
            address(spaceFactory),
            address(balancerVault)
        );
        divider.setPeriphery(address(periphery));
        poolManager.setIsTrusted(address(periphery), true);

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

        factory = deployFactory(address(target), address(reward));
        address f = periphery.deployAdapter(address(factory), address(target), ""); // deploy & onboard target through Periphery
        adapter = MockAdapter(f);
        divider.setGuard(address(adapter), 10 * 2**128);

        // users
        alice = createUser(MAX_TARGET);
        bob = createUser(MAX_TARGET);
        jim = createUser(MAX_TARGET);
    }

    function createUser(uint256 amt) public returns (User user) {
        user = new User();
        user.setFactory(factory);
        updateUser(user, target, stake, amt);
    }

    function updateUser(
        User user,
        MockTargetLike target,
        MockToken stake,
        uint256 amt
    ) public {
        user.setStake(stake);
        user.setTarget(target);
        user.setDivider(divider);
        user.setPeriphery(periphery);
        user.doApprove(address(underlying), address(periphery));
        user.doApprove(address(underlying), address(divider));
        user.doMint(address(underlying), amt);
        user.doApprove(address(stake), address(periphery));
        user.doApprove(address(stake), address(divider));
        user.doMint(address(stake), amt);
        user.doApprove(address(target), address(periphery));
        user.doApprove(address(target), address(divider));
        if (!is4626) {
            user.doMint(address(target), amt);
        } else {
            user.doMint(address(underlying), amt);
            user.doApprove(address(underlying), address(target));
            hevm.prank(address(user));
            target.deposit(amt, address(user));
        }
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
        MockToken underlying = MockToken(!is4626 ? target.underlying() : target.asset());
        uint256 issued = alice.doIssue(adapter, maturity, tBal);
        alice.doTransfer(divider.yt(adapter, maturity), address(balancerVault), issued); // we don't really need this but we transfer them anyways
        alice.doTransfer(divider.pt(adapter, maturity), address(balancerVault), issued);

        // we mint proportional underlying value. If proportion is 10%, we mint 10% more than what we've issued PT.
        if (!is4626) {
            target.mint(address(balancerVault), tBal);
        } else {
            underlying.mint(address(this), tBal);
            underlying.approve(address(target), type(uint256).max);
            tBal = target.deposit(tBal, address(this));
            target.transfer(address(balancerVault), tBal);
        }
    }

    // ---- deployers ---- //

    function deployFactory(address _target, address _reward) public returns (MockFactory someFactory) {
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: address(stake),
            oracle: ORACLE,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0
        });
        someFactory = new MockFactory(address(divider), factoryParams, _reward, !is4626 ? false : true); // deploy adapter factory
        someFactory.addTarget(_target, true);
        divider.setIsTrusted(address(someFactory), true);
        periphery.setFactory(address(someFactory), true);
    }

    function deployCropsFactory(address _target, address[] memory _rewardTokens)
        public
        returns (MockCropsFactory someFactory)
    {
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: address(stake),
            oracle: ORACLE,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0
        });
        someFactory = new MockCropsFactory(address(divider), factoryParams, _rewardTokens, !is4626 ? false : true); // deploy adapter factory
        someFactory.addTarget(_target, true);
        divider.setIsTrusted(address(someFactory), true);
        periphery.setFactory(address(someFactory), true);
    }

    function deployMockTarget(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) internal returns (address _target) {
        if (!is4626) {
            _target = address(new MockTarget(_underlying, _name, _symbol, _decimals));
        } else {
            _target = address(new MockERC4626(ERC20(_underlying), _name, _symbol));
        }
    }

    function deployMockAdapter(
        address _divider,
        address _target,
        address _reward
    ) internal returns (address _adapter) {
        if (!is4626) {
            _adapter = address(
                new MockAdapter(
                    address(_divider),
                    address(_target),
                    target.underlying(),
                    ISSUANCE_FEE,
                    DEFAULT_ADAPTER_PARAMS,
                    address(_reward)
                )
            );
        } else {
            _adapter = address(
                new Mock4626Adapter(
                    address(_divider),
                    address(_target),
                    target.asset(),
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

    function sponsorSampleSeries(address sponsor, uint256 maturity) public returns (address pt, address yt) {
        (pt, yt) = User(sponsor).doSponsorSeries(address(adapter), maturity);
    }

    function convertBase(uint256 decimals) internal pure returns (uint256) {
        uint256 base = 1;
        base = decimals > 18 ? 10**(decimals - 18) : 10**(18 - decimals);
        return base;
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
    function increaseScale() internal {
        if (!is4626) {
            hevm.warp(block.timestamp + 1 days);
        } else {
            underlying.mint(address(target), underlying.balanceOf(address(target)));
        }
    }
}
