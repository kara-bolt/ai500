// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MerkleWeights
 * @notice Library for verifying token weight proofs against a merkle root
 * @dev Leaf format: keccak256(abi.encodePacked(token, weight))
 */
library MerkleWeights {
    /**
     * @notice Verify a token's weight against the merkle root
     * @param root The merkle root to verify against
     * @param token Token address
     * @param weight Token's target weight in BPS (basis points)
     * @param proof Merkle proof path
     * @return valid True if the proof is valid
     */
    function verify(
        bytes32 root,
        address token,
        uint256 weight,
        bytes32[] calldata proof
    ) internal pure returns (bool valid) {
        bytes32 leaf = computeLeaf(token, weight);
        return processProof(proof, leaf) == root;
    }

    /**
     * @notice Verify multiple token weights in a batch
     * @param root The merkle root to verify against
     * @param tokens Array of token addresses
     * @param weights Array of token weights in BPS
     * @param proofs Array of merkle proofs
     * @return valid True if all proofs are valid
     */
    function verifyBatch(
        bytes32 root,
        address[] calldata tokens,
        uint256[] calldata weights,
        bytes32[][] calldata proofs
    ) internal pure returns (bool valid) {
        require(tokens.length == weights.length, "Length mismatch");
        require(tokens.length == proofs.length, "Length mismatch");

        for (uint256 i = 0; i < tokens.length; i++) {
            if (!verify(root, tokens[i], weights[i], proofs[i])) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice Compute the leaf hash for a token weight entry
     * @param token Token address
     * @param weight Token weight in BPS
     * @return leaf The leaf hash
     */
    function computeLeaf(
        address token,
        uint256 weight
    ) internal pure returns (bytes32 leaf) {
        // Double hash to prevent second preimage attacks
        return keccak256(abi.encodePacked(
            keccak256(abi.encodePacked(token, weight))
        ));
    }

    /**
     * @notice Process a merkle proof to compute the root
     * @param proof The merkle proof path
     * @param leaf The leaf hash
     * @return computedRoot The computed root hash
     */
    function processProof(
        bytes32[] calldata proof,
        bytes32 leaf
    ) internal pure returns (bytes32 computedRoot) {
        computedRoot = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            computedRoot = hashPair(computedRoot, proof[i]);
        }
    }

    /**
     * @notice Hash two nodes in sorted order (smaller first)
     * @dev Ensures consistent ordering regardless of proof direction
     */
    function hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b 
            ? keccak256(abi.encodePacked(a, b))
            : keccak256(abi.encodePacked(b, a));
    }

    /**
     * @notice Build a leaf with additional metadata (tier, rank)
     * @param token Token address
     * @param weight Weight in BPS
     * @param tier Token tier (1, 2, or 3)
     * @param rank Token rank (1-500)
     * @return leaf The extended leaf hash
     */
    function computeExtendedLeaf(
        address token,
        uint256 weight,
        uint8 tier,
        uint16 rank
    ) internal pure returns (bytes32 leaf) {
        return keccak256(abi.encodePacked(
            keccak256(abi.encodePacked(token, weight, tier, rank))
        ));
    }

    /**
     * @notice Verify extended leaf with tier and rank
     */
    function verifyExtended(
        bytes32 root,
        address token,
        uint256 weight,
        uint8 tier,
        uint16 rank,
        bytes32[] calldata proof
    ) internal pure returns (bool valid) {
        bytes32 leaf = computeExtendedLeaf(token, weight, tier, rank);
        return processProof(proof, leaf) == root;
    }
}
