//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract DSCEngineIntegrationTest is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    address public USER_B = makeAddr("user_B");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    function setUp() public {
        DeployDSC deployDSC = new DeployDSC();
        (dsc, engine, config) = deployDSC.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(USER_B, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    // constructor Tests //
    ///////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLLengthDoesntMatchPriceFeed() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressedAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////
    // Price Tests //
    /////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmountInWei = 30000e18;
        uint256 expectedTokenAmount = 15e18;
        uint256 actualTokenAmount = engine.getTokenAmountFromUsd(weth, usdAmountInWei);
        assertEq(expectedTokenAmount, actualTokenAmount);
    }

    /////////////////////////////
    // depositCollateral Tests //
    /////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        ranToken.approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /*function testRevertsIfTransferFailed() public {
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
    }*/

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, engine.getUsdValue(weth, AMOUNT_COLLATERAL));
    }

    function testDepositCollateralEmits() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false, address(engine));
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ///////////////////
    // mintDsc Tests //
    ///////////////////

    function testMintDsc() public {
        uint256 amountDscToMint = 1000e6; // 1000 DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountDscToMint);
        vm.stopPrank();
    }

    function testMintDscRevertsIfHealthFactorBroken() public {
        uint256 amountDscToMint = 6 ether;
        uint256 expectedHealthFactor = 1666666666666666666666;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(abi.encodePacked(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountDscToMint);
        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testRedeemCollateral() public {

        uint256 amountDsc = 1000;

        /******************************************************************************/

        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountDsc);

        dsc.approve(address(engine), amountDsc);
        ERC20Mock(weth).approveInternal(address(engine), USER, AMOUNT_COLLATERAL);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, amountDsc);

        vm.stopPrank();

        // USER approves engine to get some collateral. Then USER execute the deposit, and receive some DSC. 
        // Now, USER approves engine to burn some DSC && engine approves USER to get some collateral. And they act.

        /******************************************************************************/

        assertEq(engine.getAccountCollateralValue(USER), 0);
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    function testRedeemCollateralEmits() public depositedCollateral {

        // This test aims to demonstrate that redeemCollateral() emits.

        /******************************************************************************/

        vm.startPrank(address(engine));

        ERC20Mock(weth).approve(USER, AMOUNT_COLLATERAL);

        vm.stopPrank();

        // After some deposit stuff, engine approves USER to redeem some collateral.

        /******************************************************************************/

        vm.prank(USER);

        vm.expectEmit(true, true, true, true, address(engine));
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);

        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);

        // USER redeems the collateral. 
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    function testRedeemCollateralRevertsIfHealthFactorBroken() public {

        //This test aims to demonstrate that function redeemCollateral() reverts when Health Factor (HF) is broken (HF < min).

        uint256 amountDscToMint = 5 ether;
        uint256 amountDscToBurn = 1 ether;
        uint256 amountCollateralToRedeem = 3 ether;

        uint256 expectedHealthFactor = (7 / 4) * 1e21;

        // 7 == AMOUNT_COLLATERAL (10) - amountCollateralToRedeem (3)
        // 4 == amountDscToMint (5) - amountDscToBurn (1) 
        // Health Factor (HF) == ratio between amount of collateral (in UDS) and amount of DSC.

        /******************************************************************************/

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountDscToMint);
        dsc.approve(address(engine), amountDscToBurn);
        vm.stopPrank();

        // USER approves engine to cumulate AMOUNT_COLLATERAL. In return, USER can borrow come DSC.                                                                      

        /******************************************************************************/

        vm.startPrank(address(engine));

        ERC20Mock(weth).approve(USER, amountCollateralToRedeem);
        vm.stopPrank();

        // Now, it's engine's turn to approve USER. USER can have back a portion of his collateral deposited.

        /******************************************************************************/

        vm.expectRevert(abi.encodePacked(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));

        vm.prank(USER);

        engine.redeemCollateralForDsc(weth, amountCollateralToRedeem, amountDscToBurn);

        // Time for USER to redeem.
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////
    // burnDsc Tests //
    ///////////////////

    function testBurnDsc() public depositedCollateral {

        uint256 amountDsc = 1000e6;

        /******************************************************************************/

        vm.startPrank(USER);

        engine.mintDsc(amountDsc);
        dsc.approve(address(engine), amountDsc);
        engine.burnDsc(amountDsc);

        vm.stopPrank();

        // USER obtain some DSC. Then, he approves engine to burn it. And so it does.

        // Approval is needed, similarly to the _transfer() function

        /******************************************************************************/

        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);

        assertEq(totalDscMinted, 0);
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    /////////////////////
    // liquidate Tests //
    /////////////////////

    function testLiquidateRevertsIfHealthFactorOk() public {

        uint256 amountDsc = 5 ether;

        /******************************************************************************/

        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountDsc);

        vm.stopPrank();

        // USER approves engine to cumulate AMOUNT_COLLATERAL. In return, USER can borrow come DSC.

        /******************************************************************************/

        vm.expectRevert(abi.encodePacked(DSCEngine.DSCEngine__HealthFactorOk.selector, engine.getHealthFactor(USER)));

        vm.prank(USER_B);
        engine.liquidate(weth, USER, amountDsc);
    }

    //////////////////////////////////////////////////////////////////////////////////////////

    /////////////////////////
    // Health Factor Tests //
    /////////////////////////
}
