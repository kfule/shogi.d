import std.random;

struct Hash {
  ulong _key;
  alias _key this;

  void update(const uint to, const uint koma) @nogc { _key ^= _zobrist[koma - 4][to]; }

  static immutable ulong[81][28] _zobrist = initZobrist();
  static ulong[81][28] initZobrist() {
    ulong[81][28] z;
    Random gen;
    gen.seed(77);
    foreach (koma_i; 4..32)
      foreach (square_i; 0..81) { z[koma_i - 4][square_i] = uniform(ulong.min, ulong.max, gen) << 1; }
    return z;
  }
}
