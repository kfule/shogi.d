import std.random;

struct Hash {
  ulong _key;
  alias _key this;

  void update(uint to, uint koma) @nogc { _key ^= _zobrist[koma][to]; }

  static immutable ulong[82][32] _zobrist = initZobrist();
  static ulong[82][32] initZobrist() {
    ulong[82][32] z;
    Random gen;
    gen.seed(77);
    foreach (koma_i; 4..32)
      foreach (square_i; 0..81) { z[koma_i][square_i] = uniform(ulong.min, ulong.max, gen) << 1; }
    return z;
  }
}
