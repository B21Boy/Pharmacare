/// Explicit int/double clamps. (`int.clamp` is typed `num` on some SDKs.)
int clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

double clampDouble01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
