//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {IWETH, IBTC} from "../../src/Interfaces.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MockDSCEngine} from "../mocks/MockDSCEngine.sol";
import {MockMintFailed} from "../mocks/MockMintFailed.sol";
import {MockTransferFailed} from "../mocks/MockTransferFailed.sol";
import {MockDscTransferFailed} from "../mocks/MockDscTransferFailed.sol";
import {MockRedeemFailed} from "../mocks/MockRedeemFailed.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineUnitTest is Test {
    error DSCEngineUnitTest__MustBeAnvil();
    error DSCEngineUnitTest__MustBeSepolia();

    DSCEngine public engine;
    DecentralizedStableCoin public dsc;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    address public USER = makeAddr("user");
    uint256 public constant USER_BALANCE = 1e18;
    uint256 public constant FRACTION = 1e15;
    uint256 fractionToDeposit = USER_BALANCE / FRACTION;

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    modifier Forking() {
        if (block.chainid == 11155111) {
            vm.prank(USER);
            (bool success, bytes memory data) = tokenAddresses[0].call{value: USER_BALANCE}("0xd0e30db0");
            vm.prank(USER);
            IERC20(tokenAddresses[0]).approve(address(engine), uint256(fractionToDeposit));
        } else {
            ERC20Mock(tokenAddresses[0]).mint(USER, USER_BALANCE);
            ERC20Mock(tokenAddresses[0]).approveInternal(USER, address(engine), fractionToDeposit);
        }
        _;
    }

    function setUp() public {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc,) = config.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        dsc = new DecentralizedStableCoin();
        engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(engine));
        vm.deal(USER, USER_BALANCE);
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    
    ///////////////////////
    // constructor Tests //
    ///////////////////////

    function testConstructorRevertsIfTokenAddressedAndPriceFeedAddressesAreNotSameLength() public {
        DSCEngine engineTest;
        address[] memory wrongTokenAddresses = new address[](tokenAddresses.length + 1);
        vm.expectRevert();
        engineTest = new DSCEngine(wrongTokenAddresses, priceFeedAddresses, address(dsc));
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    function testConstructoGenerateCorrectlyImmutableDsc() public Forking {
        uint256 amountDscToMint;
        uint256 threshold = 3;
        amountDscToMint = fractionToDeposit / threshold;
        vm.prank(USER);
        engine.depositCollateral(tokenAddresses[0], fractionToDeposit);
        vm.prank(USER);
        engine.mintDsc(amountDscToMint);
    }

    //////////////////////////////////////////////////////////////////////////////////////////

     ////////////////////////////
    // depositCollateral Tests //
    /////////////////////////////

    function testDepositCollateralEmits() public Forking {
        vm.expectEmit(true, true, true, false, address(engine));
        vm.prank(USER);
        emit CollateralDeposited(USER, tokenAddresses[0], fractionToDeposit);
        engine.depositCollateral(tokenAddresses[0], fractionToDeposit);
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    function testDepositCollateralRevertsMoreThanZero() public Forking {
        vm.expectRevert();
        vm.prank(USER);
        engine.depositCollateral(tokenAddresses[0], 0);
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    function testDepositCollateralRevertsIsAllowedToken() public Forking {
        vm.expectRevert();
        vm.prank(USER);
        engine.depositCollateral(address(1), fractionToDeposit);
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    function testRevertsIfTransferFailed() public {

        MockTransferFailed mockCollateral =
            new MockTransferFailed("Mock Collateral", "MOCO", USER, STARTING_ERC20_BALANCE);
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc,) = config.activeNetworkConfig();
        tokenAddresses = [weth, wbtc, address(mockCollateral)];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed, wethUsdPriceFeed];

        // In this Mock we set the return of transferFrom() function equal to false (modifying ERC20 contract), in order to not avoid _redeemCollateral()'s filter. 

        DecentralizedStableCoin mockDsc = new DecentralizedStableCoin();
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockEngine));

        /******************************************************************************/

        vm.startPrank(USER);

        MockTransferFailed(tokenAddresses[2]).mint(USER, USER_BALANCE);
        MockTransferFailed(tokenAddresses[2]).approveInternal(USER, address(mockEngine), fractionToDeposit);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);

        mockEngine.depositCollateral(tokenAddresses[2], fractionToDeposit);

        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////
    // mintDsc Tests //
    ///////////////////

    function testRevertsIfMintFailed() public {

        uint256 amountDsc = fractionToDeposit / 3;

        MockMintFailed mockDsc = new MockMintFailed();
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockEngine));

         // In this Mock we set the return of mint() function equal to false (modifying DSC contract), in order to not avoid mintdsc()'s filter.

        /******************************************************************************/

        vm.startPrank(USER);

        ERC20Mock(tokenAddresses[0]).mint(USER, USER_BALANCE);
        ERC20Mock(tokenAddresses[0]).approveInternal(USER, address(mockEngine), fractionToDeposit);
        mockDsc.approve(address(mockEngine), amountDsc);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);

        mockEngine.depositCollateralAndMintDsc(tokenAddresses[0], fractionToDeposit, amountDsc);

        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////
    // burnDsc Tests //
    ///////////////////

    function testBurnDscRevertsIfTransferFailed() public {

        uint256 amountDsc = fractionToDeposit / 3;

        MockDscTransferFailed mockDsc = new MockDscTransferFailed();
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockEngine));

         // In this Mock we set the return of transferFrom() function equal to false (modifying DSC contract), in order to not avoid _burnDsc()'s filter.

        /******************************************************************************/

        vm.startPrank(USER);

        ERC20Mock(tokenAddresses[0]).mint(USER, USER_BALANCE);
        ERC20Mock(tokenAddresses[0]).approveInternal(USER, address(mockEngine), fractionToDeposit);
        mockDsc.approve(address(mockEngine), amountDsc);
        mockEngine.depositCollateralAndMintDsc(tokenAddresses[0], fractionToDeposit, amountDsc);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);

        mockEngine.burnDsc(amountDsc);

        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    ////////////////////////////
    // redeemCollateral Tests //
    ////////////////////////////

    function testRedeemCollateralRevertsIfTransferFailed() public {

        uint256 amountDsc = fractionToDeposit / 3;
        
        MockRedeemFailed mockCollateral = new MockRedeemFailed("Mock Collateral", "MOCO", USER, STARTING_ERC20_BALANCE);

        // In this Mock we set the return of transfer() function equal to false (modifying ERC20 contract), in order to not avoid _redeemCollateral()'s filter. 

        /******************************************************************************/

        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc,) = config.activeNetworkConfig();
        tokenAddresses = [weth, wbtc, address(mockCollateral)];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed, wethUsdPriceFeed];

        // We've used the new kind of collateral.

        DecentralizedStableCoin mockDsc = new DecentralizedStableCoin();
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockEngine));

        /******************************************************************************/

        vm.startPrank(USER);

        ERC20Mock(tokenAddresses[2]).mint(USER, USER_BALANCE);
        ERC20Mock(tokenAddresses[2]).approveInternal(USER, address(mockEngine), fractionToDeposit);
        mockDsc.approve(address(mockEngine), amountDsc);
        mockEngine.depositCollateralAndMintDsc(tokenAddresses[2], fractionToDeposit, amountDsc);
        mockEngine.burnDsc(amountDsc);

        // USER gets the new kind of collateral, and deposit a part of it on mockEngine (approved), immediately receiving some DSC. Then, this amount of DSC, after approval, is burnt. this is the setup we needed in order to demonstrate redeemCollateral() to revert as wanted./******************************************************************************/

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);

        mockEngine.redeemCollateral(tokenAddresses[2], fractionToDeposit);

        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    /////////////////////
    // Liquidate Tests //
    /////////////////////

    function testMockLiquidateRevertsIfHealthFactorNotImproved() public {

        DecentralizedStableCoin mockDsc = new DecentralizedStableCoin();
        MockDSCEngine mockEngine = new MockDSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockEngine));

        // The Mock is more severe, and endingUserHealthFactor > MIN_HEALTH_FACTOR. 

        /******************************************************************************/

        address USER_B = makeAddr("user_B");

        ERC20Mock(tokenAddresses[0]).mint(USER_B, STARTING_ERC20_BALANCE * 10);
        ERC20Mock(tokenAddresses[0]).mint(USER, STARTING_ERC20_BALANCE);

        uint256 amountDsc = 6 ether;
        uint256 amountDsc_B = 0.5 ether; // In order to improve USER's HF, should be at least == 1. 

        /******************************************************************************/

        vm.startPrank(USER);

        ERC20Mock(tokenAddresses[0]).approve(address(mockEngine), AMOUNT_COLLATERAL);
        mockEngine.depositCollateralAndMintDsc(tokenAddresses[0], AMOUNT_COLLATERAL, amountDsc);

        vm.stopPrank();

        /******************************************************************************/

        vm.startPrank(USER_B);

        ERC20Mock(tokenAddresses[0]).approve(address(mockEngine), AMOUNT_COLLATERAL * 10);
        mockEngine.depositCollateralAndMintDsc(tokenAddresses[0], AMOUNT_COLLATERAL * 10, amountDsc_B);
        mockDsc.approve(address(mockEngine), amountDsc_B);

        vm.expectRevert(MockDSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        mockEngine.liquidate(tokenAddresses[0], USER, amountDsc_B);

        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    function testMockLiquidateRevertsIfHealthFactorBroken() public {

        // // This test aims to demonstrate that liquidate() reverts if HF is broken. It is used a Mock in order to avoid liquidate()'s filters.

        /******************************************************************************/

        DecentralizedStableCoin mockDsc = new DecentralizedStableCoin();
        MockDSCEngine mockEngine = new MockDSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockEngine));

        // In this Mock mintDsc() cannot revert if HF is broken. 

        /******************************************************************************/

        address USER_B = makeAddr("user_B");

        ERC20Mock(tokenAddresses[0]).mint(USER_B, STARTING_ERC20_BALANCE);
        ERC20Mock(tokenAddresses[0]).mint(USER, STARTING_ERC20_BALANCE);

        uint256 amountDsc = 6 ether;

        /******************************************************************************/

        vm.startPrank(USER);
        ERC20Mock(tokenAddresses[0]).approve(address(mockEngine), AMOUNT_COLLATERAL);
        mockEngine.depositCollateralAndMintDsc(tokenAddresses[0], AMOUNT_COLLATERAL, amountDsc);
        vm.stopPrank();

        vm.startPrank(USER_B);
        ERC20Mock(tokenAddresses[0]).approve(address(mockEngine), AMOUNT_COLLATERAL);
        mockEngine.depositCollateralAndMintDsc(tokenAddresses[0], AMOUNT_COLLATERAL, amountDsc); // USER_B's HF will be broken, because he is in the same condition of USER.
    
        mockDsc.approve(address(mockEngine), amountDsc);

        /******************************************************************************/

        vm.expectRevert(
            abi.encodePacked(MockDSCEngine.DSCEngine__BreaksHealthFactor.selector, mockEngine.getHealthFactor(USER))
        );
        mockEngine.liquidate(tokenAddresses[0], USER, amountDsc);

        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    function testLiquidateRevertsIfHealthFactorNotImproved() public {

        // This test aims to demonstrate that liquidate() reverts if HF is not improved. It is used a Mock in order to avoid liquidate()'s filters.

        /******************************************************************************/

        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(priceFeedAddresses[0]);
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockEngine));

        // This Mock crash the value of the collateral (by crashing the one of USD) when burn() is called. 

        /******************************************************************************/

        address USER_B = makeAddr("user_B");

        ERC20Mock(tokenAddresses[0]).mint(USER_B, STARTING_ERC20_BALANCE * 10);
        ERC20Mock(tokenAddresses[0]).mint(USER, STARTING_ERC20_BALANCE);

        uint256 amountDsc = 5 ether;
        uint256 amountDsc_B = 4 ether;

        /******************************************************************************/

        vm.startPrank(USER);

        ERC20Mock(tokenAddresses[0]).approve(address(mockEngine), AMOUNT_COLLATERAL);
        mockEngine.depositCollateralAndMintDsc(tokenAddresses[0], AMOUNT_COLLATERAL, amountDsc);

        vm.stopPrank();

        // Time for USER.

        /******************************************************************************/

        // Time for USER_B, which will liquidate USER.
        
        vm.startPrank(USER_B); 

        ERC20Mock(tokenAddresses[0]).approve(address(mockEngine), AMOUNT_COLLATERAL * 10);
        mockEngine.depositCollateralAndMintDsc(tokenAddresses[0], AMOUNT_COLLATERAL * 10, amountDsc_B);

        /** Same steps as USER, but with an increasing factor, in order to be able to liquidate USER. */

        mockDsc.approve(address(mockEngine), amountDsc_B); // Approval needed in order to liquidate USER.

        MockV3Aggregator(priceFeedAddresses[0]).updateAnswer(20e8); // Necessary, otherwise HF would be ok and there wouldn't be any liquidation needed.

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);

        mockEngine.liquidate(tokenAddresses[0], USER, amountDsc_B);

        vm.stopPrank();

        //
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    function testMockLiquidate() public {

        DecentralizedStableCoin mockDsc = new DecentralizedStableCoin();
        MockDSCEngine mockEngine = new MockDSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockEngine));

        address USER_B = makeAddr("user_B");

        ERC20Mock(tokenAddresses[0]).mint(USER_B, STARTING_ERC20_BALANCE * 10);
        ERC20Mock(tokenAddresses[0]).mint(USER, STARTING_ERC20_BALANCE);

        uint256 amountDsc = 6 ether;

        vm.startPrank(USER);
        ERC20Mock(tokenAddresses[0]).approve(address(mockEngine), AMOUNT_COLLATERAL);
        mockEngine.depositCollateralAndMintDsc(tokenAddresses[0], AMOUNT_COLLATERAL, amountDsc);
        vm.stopPrank();

        vm.startPrank(USER_B);
        ERC20Mock(tokenAddresses[0]).approve(address(mockEngine), AMOUNT_COLLATERAL * 10);
        mockEngine.depositCollateralAndMintDsc(tokenAddresses[0], AMOUNT_COLLATERAL * 10, amountDsc);
        mockDsc.approve(address(mockEngine), amountDsc);
        
        mockEngine.liquidate(tokenAddresses[0], USER, amountDsc);
        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////
    // Getter Tests //
    ///////////////////

    function testGetAccountCollateralValue() public Forking {

        uint256 expectedValue = 2e3 * fractionToDeposit;

        vm.startPrank(USER);
        engine.depositCollateral(tokenAddresses[0], fractionToDeposit);
        vm.stopPrank();

        uint256 actualValue = engine.getAccountCollateralValue(USER);

        assertEq(expectedValue, actualValue);
    }
}
