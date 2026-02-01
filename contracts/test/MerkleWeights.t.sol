// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "./helpers/MerkleWeightsHarness.sol";

contract MerkleWeightsTest is Test {
    MerkleWeightsHarness public harness;

    // Test tokens
    address token1 = address(0x1);
    address token2 = address(0x2);
    address token3 = address(0x3);
    address token4 = address(0x4);

    // Test weights (BPS)
    uint256 weight1 = 200;  // 2%
    uint256 weight2 = 200;  // 2%
    uint256 weight3 = 150;  // 1.5%
    uint256 weight4 = 100;  // 1%

    function setUp() public {
        harness = new MerkleWeightsHarness();
    }

    function test_ComputeLeaf() public view {
        address token = address(0x123);
        uint256 weight = 200;

        bytes32 leaf = harness.computeLeaf(token, weight);

        // Leaf should be double-hashed
        bytes32 inner = keccak256(abi.encodePacked(token, weight));
        bytes32 expected = keccak256(abi.encodePacked(inner));

        assertEq(leaf, expected);
    }

    function test_HashPair_Ordering() public view {
        bytes32 a = bytes32(uint256(1));
        bytes32 b = bytes32(uint256(2));

        // Should produce same result regardless of order
        bytes32 result1 = harness.hashPair(a, b);
        bytes32 result2 = harness.hashPair(b, a);

        assertEq(result1, result2);
    }

    function test_VerifySimpleMerkleTree() public view {
        // Build a simple 2-leaf tree
        bytes32 leaf1 = harness.computeLeaf(address(0x1), 200);
        bytes32 leaf2 = harness.computeLeaf(address(0x2), 150);
        bytes32 root = harness.hashPair(leaf1, leaf2);

        // Proof for leaf1 is just leaf2
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leaf2;

        bool valid = harness.verify(root, address(0x1), 200, proof);
        assertTrue(valid);

        // Proof for leaf2 is just leaf1
        proof[0] = leaf1;
        valid = harness.verify(root, address(0x2), 150, proof);
        assertTrue(valid);
    }

    function test_Verify4LeafTree() public view {
        // Build leaves
        bytes32 leaf1 = harness.computeLeaf(token1, weight1);
        bytes32 leaf2 = harness.computeLeaf(token2, weight2);
        bytes32 leaf3 = harness.computeLeaf(token3, weight3);
        bytes32 leaf4 = harness.computeLeaf(token4, weight4);

        // Build tree
        bytes32 node12 = harness.hashPair(leaf1, leaf2);
        bytes32 node34 = harness.hashPair(leaf3, leaf4);
        bytes32 root = harness.hashPair(node12, node34);

        // Verify token1 (proof: [leaf2, node34])
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leaf2;
        proof[1] = node34;
        assertTrue(harness.verify(root, token1, weight1, proof));

        // Verify token3 (proof: [leaf4, node12])
        proof[0] = leaf4;
        proof[1] = node12;
        assertTrue(harness.verify(root, token3, weight3, proof));
    }

    function test_VerifyBatch() public view {
        // Build simple 2-leaf tree
        bytes32 leaf1 = harness.computeLeaf(token1, weight1);
        bytes32 leaf2 = harness.computeLeaf(token2, weight2);
        bytes32 root = harness.hashPair(leaf1, leaf2);

        address[] memory tokens = new address[](2);
        tokens[0] = token1;
        tokens[1] = token2;

        uint256[] memory weights = new uint256[](2);
        weights[0] = weight1;
        weights[1] = weight2;

        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = leaf2;
        proofs[1] = new bytes32[](1);
        proofs[1][0] = leaf1;

        assertTrue(harness.verifyBatch(root, tokens, weights, proofs));
    }

    function test_InvalidProof() public view {
        bytes32 leaf1 = harness.computeLeaf(address(0x1), 200);
        bytes32 leaf2 = harness.computeLeaf(address(0x2), 150);
        bytes32 root = harness.hashPair(leaf1, leaf2);

        // Wrong weight should fail
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leaf2;

        bool valid = harness.verify(root, address(0x1), 999, proof);
        assertFalse(valid);
    }

    function test_WrongProof() public view {
        bytes32 leaf1 = harness.computeLeaf(address(0x1), 200);
        bytes32 leaf2 = harness.computeLeaf(address(0x2), 150);
        bytes32 root = harness.hashPair(leaf1, leaf2);

        // Wrong proof element
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(uint256(12345));

        bool valid = harness.verify(root, address(0x1), 200, proof);
        assertFalse(valid);
    }

    function test_ExtendedLeaf() public view {
        address token = address(0x123);
        uint256 weight = 200;
        uint8 tier = 1;
        uint16 rank = 5;

        bytes32 leaf = harness.computeExtendedLeaf(token, weight, tier, rank);

        bytes32 inner = keccak256(abi.encodePacked(token, weight, tier, rank));
        bytes32 expected = keccak256(abi.encodePacked(inner));

        assertEq(leaf, expected);
    }

    function test_VerifyExtended() public view {
        uint8 tier1 = 1;
        uint16 rank1 = 1;
        uint8 tier2 = 2;
        uint16 rank2 = 51;

        bytes32 leaf1 = harness.computeExtendedLeaf(token1, weight1, tier1, rank1);
        bytes32 leaf2 = harness.computeExtendedLeaf(token2, weight2, tier2, rank2);
        bytes32 root = harness.hashPair(leaf1, leaf2);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leaf2;

        assertTrue(harness.verifyExtended(root, token1, weight1, tier1, rank1, proof));
    }

    function testFuzz_LeafUniqueness(
        address tokenA,
        address tokenB,
        uint256 weightA,
        uint256 weightB
    ) public view {
        vm.assume(tokenA != tokenB || weightA != weightB);

        bytes32 leafA = harness.computeLeaf(tokenA, weightA);
        bytes32 leafB = harness.computeLeaf(tokenB, weightB);

        // Different inputs should produce different leaves
        assertNotEq(leafA, leafB);
    }
}
