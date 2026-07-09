#ifndef RULES_CUDA_TOOLKIT_EXAMPLES_VECTOR_ADD_H_
#define RULES_CUDA_TOOLKIT_EXAMPLES_VECTOR_ADD_H_

// Computes out[i] = a[i] + b[i] on the GPU for i in [0, n).
// Returns cudaSuccess (0) on success, or a CUDA error code otherwise.
int VectorAdd(const float* a, const float* b, float* out, int n);

#endif  // RULES_CUDA_TOOLKIT_EXAMPLES_VECTOR_ADD_H_
