# BetterRadar

## Description

This project is a continuation of the Epitech "my_radar" project. Its main goal is to push optimization to the absolute limit. While the original base project struggles to manage a massive number of entities, this improved version is fully capable of handling and rendering **100,000 ships at 60 FPS**.

## Demo

https://github.com/user-attachments/assets/c2492b4d-4eed-4944-a368-063be1ff93fd

## How to run

The project was written in [Zig](https://ziglang.org/) 0.15.2

To run the project with maximum optimizations (critical for high performance):

```bash
zig build release
```

The generated executable will be located in `zig-out/bin/betterradar`.

## Optimizations implemented

To reach the 100k entities at 60 FPS milestone, several major optimizations were introduced:

- **SIMD Instructions:** Intensive calculations, such as updating ship positions and checking distances, are vectorized using SIMD (Single Instruction, Multiple Data). This allows the CPU to process multiple entities in a single clock cycle, significantly maximizing throughput and reducing overall computation time.
- **Uniform Grid:** Collision detection is no longer done naively by testing every ship against every other ship (which would result in an $O(n^2)$ complexity). By using a spatial grid structure (`uniform_grid.zig`), space is partitioned into cells. Thus, to detect a collision, a ship is only compared against entities in its own cell or adjacent ones, drastically reducing the required calculations.
- **Avoiding dynamic allocations:** Optimization relies on smart allocation and the use of tailored data structures, minimizing bottlenecks caused by runtime memory management.
