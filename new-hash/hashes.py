from typing import Callable
import numpy as np
from functools import partial


def original_part_hash(obj: np.uint32, seed: np.uint32 = np.uint32(0)) -> np.uint32:
    """
    Original hash function for integers.

    Args:
        obj (uint32): The 32-bit object id
        seed (uint32, optional): The seed value. Defaults to 0.

    Returns:
        uint32: The computed hash value (11 bits).
    """

    def rotate_left(value: np.uint32, amount: np.uint32) -> np.uint32:
        return (value << amount) | (value >> (32 - amount))

    obj_bytes = obj >> np.array([0, 8, 16, 24], dtype=np.uint32) & np.uint32(0xFF)

    seed ^= obj_bytes[0]
    seed = rotate_left(seed, np.uint32(5))

    seed ^= obj_bytes[1]
    seed = rotate_left(seed, np.uint32(11))

    seed ^= obj_bytes[2]
    seed = rotate_left(seed, np.uint32(18))

    seed ^= obj_bytes[3]

    lower_bits = seed & np.uint32(0x7FF)
    upper_bits = (seed >> np.uint32(11)) & np.uint32(0x1FFFFF)

    lower_bits ^= upper_bits & np.uint32(0x7FF)
    lower_bits ^= upper_bits >> np.uint32(10)

    lower_bits = (
        ((lower_bits & np.uint32(0xFF)) << np.uint32(3)) | (lower_bits >> np.uint32(8))
    ) ^ (((lower_bits & np.uint32(0x7)) << np.uint32(8)) | (lower_bits >> np.uint32(3)))

    return lower_bits


original_hashes = [
    partial(original_part_hash, seed=np.uint32(seed))
    for seed in [0x9E3779B1, 0x85EBCA77, 0xC2B2AE3D, 0x27D4EB2F]
]


# def fibonacci_hash(obj: np.uint32) -> np.uint32:
#     """
#     Fibonacci hash function for integers.

#     Args:
#         obj (uint32): The 32-bit object id

#     Returns:
#         uint32: The computed hash value (11 bits).
#     """
#     fib_constant = np.uint32(0x9E3779B9)  # 2^32 / golden ratio
#     hashed_value = obj * fib_constant
#     return (hashed_value >> np.uint32(21)) & np.uint32(0x7FF)


# Can we generate (n_part * index_length) bits and use only the bits in position k*n_part + i?
def fibonacci_hash(obj: np.uint32, n_bits: int = 11) -> np.uint64:
    """
    Fibonacci hash function for integers.

    Args:
        obj (uint32): The 32-bit object id
        n_bits (int, optional): Number of bits to return. Defaults to 11.

    Returns:
        uint32: The computed hash value (n_bits bits).
    """
    fib_constant = int((1 << (n_bits)) // ((1 + 5 ** 0.5) / 2)) | 1  # Ensure odd
    hashed_value = int(obj) * fib_constant
    return np.uint64((hashed_value >> (64 - n_bits)) & ((1 << n_bits) - 1))


def make_interleaved_fibonacci_hashes(n_parts: int, index_length: int) -> list[Callable[[np.uint32, int], np.uint32]]:
    """
    Create an interleaved Fibonacci hash function.

    Args:
        n_parts (int): Number of parts to interleave.
        index_length (int): Length of the index in bits.

    Returns:
        Callable[[uint32, int], uint32]: The interleaved Fibonacci hash function.
    """

    total_bits = n_parts * index_length

    def interleaved_fibonacci_hash(obj: np.uint32, part_index: int) -> np.uint32:
        full_hash = fibonacci_hash(obj, n_bits=total_bits)
        result = np.uint32(0)
        for bit_position in range(index_length):
            source_bit_position = part_index + bit_position * n_parts
            bit_value = (full_hash >> source_bit_position) & np.uint64(1)
            result |= np.uint32(bit_value << bit_position)
        return result

    return [partial(interleaved_fibonacci_hash, part_index=i) for i in range(n_parts)]

interleaved_fibonacci_hashes_4_11 = make_interleaved_fibonacci_hashes(4, 11)