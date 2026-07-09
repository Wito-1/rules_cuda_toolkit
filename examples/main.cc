#include <cstdio>
#include <vector>

#include "vector_add.h"

int main() {
  const int n = 1024;
  std::vector<float> a(n), b(n), out(n);
  for (int i = 0; i < n; ++i) {
    a[i] = static_cast<float>(i);
    b[i] = static_cast<float>(2 * i);
  }

  int err = VectorAdd(a.data(), b.data(), out.data(), n);
  if (err != 0) {
    std::fprintf(stderr, "VectorAdd failed with CUDA error %d\n", err);
    return 1;
  }

  std::printf("out[0]=%.1f out[%d]=%.1f\n", out[0], n - 1, out[n - 1]);
  return 0;
}
