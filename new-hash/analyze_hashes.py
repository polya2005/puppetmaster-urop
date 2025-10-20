from hashes import (
    original_hashes,
    interleaved_fibonacci_hashes_4_11,
    interleaved_fibonacci_hashes_8_8,
)
import numpy as np
from typing import Callable, Optional
from tqdm import tqdm
import matplotlib.pyplot as plt


def analyze_hash(
    hashes: list[Callable[[np.unsignedinteger], np.unsignedinteger]],
    num_samples: int = 100000,
    max_value: int = 2048,
    file_prefix: Optional[list[str]] = None,
) -> None:
    """
    Analyze the distribution of hash values for a given hash function.

    Args:
        hash (Callable[[int], list[int]]): The hash function to analyze.
        num_samples (int, optional): The number of samples to generate. Defaults to 100000.
    """
    l_samples: set[np.uint32] = set()
    for _ in tqdm(range(num_samples), desc="Generating samples"):
        sample = np.random.randint(0, 2**32, dtype=np.uint32)
        while sample in l_samples:
            sample = np.random.randint(0, 2**32, dtype=np.uint32)
        l_samples.add(sample)

    samples = np.array(list(l_samples), dtype=np.uint32)
    hash_values: list[np.ndarray] = []

    for i, h in enumerate(hashes):
        hash_values.append(
            np.array(
                [h(s) for s in tqdm(samples, desc=f"Hashing with function {i + 1}")],
                dtype=np.uint32,
            )
        )
        print(f"Hash function analysis {i + 1}:")
        frequencies = np.bincount(hash_values[i], minlength=max_value)
        print(
            f"Standard Deviation / Mean: {np.std(frequencies) / np.mean(frequencies)}"
        )

        plt.figure(figsize=(12, 6))
        plt.bar(range(len(frequencies)), frequencies)
        plt.title(f"Hash Function {i + 1} - Frequency Distribution")
        plt.xlabel("Hash Value")
        plt.ylabel("Frequency")
        if file_prefix is not None:
            plt.savefig(f"{file_prefix[i]}_hash_distribution.png")
        else:
            plt.savefig(f"hash_function_{i + 1}_distribution.png")
        plt.close()


if __name__ == "__main__":
    analyze_hash(
        interleaved_fibonacci_hashes_4_11 + interleaved_fibonacci_hashes_8_8,
        num_samples=1000000,
        max_value=256,
        file_prefix=[f"interleaved_fib_4_11_part_{i}" for i in range(4)]
        + [f"interleaved_fib_8_8_part_{i}" for i in range(8)],
    )
