#include <cmath>
#include <cstdio>
#include <vector>

#include "vector_add.h"

int main() {
  const int n = 256;
  std::vector<float> a(n), b(n), out(n);
  for (int i = 0; i < n; ++i) {
    a[i] = static_cast<float>(i);
    b[i] = static_cast<float>(i) * 3.0f;
  }

  int err = VectorAdd(a.data(), b.data(), out.data(), n);
  if (err != 0) {
    std::fprintf(stderr, "VectorAdd failed with CUDA error %d\n", err);
    return 1;
  }

  for (int i = 0; i < n; ++i) {
    float expected = a[i] + b[i];
    if (std::fabs(out[i] - expected) > 1e-5f) {
      std::fprintf(stderr, "mismatch at %d: got %.3f want %.3f\n", i, out[i],
                   expected);
      return 1;
    }
  }
  std::printf("PASS\n");
  return 0;
}
