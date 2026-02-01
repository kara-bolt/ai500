// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../src/libraries/MerkleWeights.sol";

/**
 * @title MerkleWeightsHarness
 * @notice Test harness that wraps MerkleWeights library with memory-compatible functions
 */
contract MerkleWeightsHarness {
    function verify(
        bytes32 root,
        address token,
        uint256 weight,
        bytes32[] calldata proof
    ) external pure returns (bool) {
        return MerkleWeights.verify(root, token, weight, proof);
    }

    function verifyBatch(
        bytes32 root,
        address[] calldata tokens,
        uint256[] calldata weights,
        bytes32[][] calldata proofs
    ) external pure returns (bool) {
        return MerkleWeights.verifyBatch(root, tokens, weights, proofs);
    }

    function computeLeaf(
        address token,
        uint256 weight
    ) external pure returns (bytes32) {
        return MerkleWeights.computeLeaf(token, weight);
    }

    function computeExtendedLeaf(
        address token,
        uint256 weight,
        uint8 tier,
        uint16 rank
    ) external pure returns (bytes32) {
        return MerkleWeights.computeExtendedLeaf(token, weight, tier, rank);
    }

    function verifyExtended(
        bytes32 root,
        address token,
        uint256 weight,
        uint8 tier,
        uint16 rank,
        bytes32[] calldata proof
    ) external pure returns (bool) {
        return MerkleWeights.verifyExtended(root, token, weight, tier, rank, proof);
    }

    function hashPair(bytes32 a, bytes32 b) external pure returns (bytes32) {
        return MerkleWeights.hashPair(a, b);
    }

    function processProof(
        bytes32[] calldata proof,
        bytes32 leaf
    ) external pure returns (bytes32) {
        return MerkleWeights.processProof(proof, leaf);
    }
}
