#include <cuda_runtime.h>

#include "vector_add.h"

namespace {

__global__ void VectorAddKernel(const float* a, const float* b, float* out,
                                 int n) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) {
    out[i] = a[i] + b[i];
  }
}

}  // namespace

int VectorAdd(const float* a, const float* b, float* out, int n) {
  float *d_a = nullptr, *d_b = nullptr, *d_out = nullptr;
  size_t bytes = static_cast<size_t>(n) * sizeof(float);

  cudaError_t err = cudaMalloc(&d_a, bytes);
  if (err != cudaSuccess) return err;
  err = cudaMalloc(&d_b, bytes);
  if (err != cudaSuccess) return err;
  err = cudaMalloc(&d_out, bytes);
  if (err != cudaSuccess) return err;

  cudaMemcpy(d_a, a, bytes, cudaMemcpyHostToDevice);
  cudaMemcpy(d_b, b, bytes, cudaMemcpyHostToDevice);

  int threads = 256;
  int blocks = (n + threads - 1) / threads;
  VectorAddKernel<<<blocks, threads>>>(d_a, d_b, d_out, n);

  err = cudaGetLastError();
  if (err == cudaSuccess) {
    cudaMemcpy(out, d_out, bytes, cudaMemcpyDeviceToHost);
    err = cudaDeviceSynchronize();
  }

  cudaFree(d_a);
  cudaFree(d_b);
  cudaFree(d_out);
  return err;
}
