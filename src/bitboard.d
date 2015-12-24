/**
 * ビットボード関連
 */
import std.algorithm;
import std.compiler; //vendor == Vendor.llvm
import std.conv;
import std.string;
import std.format;
import core.simd;
import shogiban;

version(LDC) {
  import ldc.gccbuiltins_x86;
  import ldc.intrinsics;
  uint bsf(T)(T src) { return cast(uint) llvm_cttz(src, true); }
  uint popCnt(T)(T x) { return cast(uint) llvm_ctpop(x); }
}
version(DigitalMars) {
  import core.bitop;
  alias popCnt = _popcnt;  //これだとpopcnt命令を使っててもインライン展開はされないかも
}

//ビットボードの片面でforeachを使うためのおまじない
struct BitwiseRange(T, uint offset = 0) {
  T a;
  this(T b) { a = b; }
  @property bool empty() {
    return !cast(bool)a;
  }
  @property uint front() {
    return bsf(a) + offset;
  }
  void popFront() { a &= a - 1; }
}

///ビットボード
struct Bitboard {
  union {
    ulong[2] b;  //コンパイル時変数の初期化周りのバグの回避のためにulong[2]を先に定義している
    ulong2 a;
  };

  ///コンストラクタ
  this(in Bitboard bb) @nogc { this = bb; }
  /// ditto
  this(in ulong2 b) @nogc { a = b; }
  /// ditto
  this(in ulong b0, in ulong b1) @nogc { b = [ b0, b1 ]; }

  //演算子
  Bitboard opBinary(string op)(const Bitboard bb) @nogc const { return mixin("Bitboard(a" ~op ~"bb.a)"); }
  Bitboard opUnary(string op)() @nogc const if (op == "~") { return Bitboard(~a); }
  //複合代入
  ref Bitboard opOpAssign(string op)(const Bitboard bb) @nogc if (op != "=") {
    a = opBinary !op(bb).a;
    return this;
  }
  bool opCast(T)() const if (is(T == bool)&&vendor == Vendor.llvm) { return !__builtin_ia32_ptestz128(a, a); }
  bool opCast(T)() const if (is(T == bool)&&vendor != Vendor.llvm) { return cast(bool)(b[0] | b[1]); }

  /// forCompileTime
  Bitboard not() @nogc const { return Bitboard(~b[0], ~b[1]); }

  ///ビット数を数える
  uint popCnt() @nogc const { return.popCnt(b[0]) +.popCnt(b[1] & ~0x7FFFFFFFFFFFUL); }

  /// 最小位ビットを返す
  uint lsb() @nogc const { return b[0] ? b[0].bsf() : (b[1].bsf() + 17); }

  string toString() const {
    string s;
    foreach (i; 0..9) {
      foreach_reverse(j; 0..9) { s ~= (this & MASK_SQ[i * 9 + j]) ? "●" : "・"; }
      s ~= " ";
      foreach_reverse(j; 0..9) { s ~= (i * 9 + j < 64) ? ((b[0] & MASK_SQ[i * 9 + j].b[0]) ? "●" : "・") : "  "; }
      s ~= " ";
      foreach_reverse(j; 0..9) { s ~= (i * 9 + j >= 17) ? ((b[1] & MASK_SQ[i * 9 + j].b[1]) ? "●" : "・") : "  "; }
      s ~= "\n";
    }
    return s;
  }

  /// 飛車角の利き算出用ハッシュ値の計算
  auto computeHash(const Bitboard mask) @nogc const {
    return ((((b[0] & mask.b[0]) << 4) | (b[1] & mask.b[1])) * 0x102040810204081UL) >> 57;
  }
  Bitboard ATTACKS_BKY(uint sq) @nogc const { return _ATTACKS_BKY[(sq << 7) | computeHash(_MASK_FILE[sq])]; }
  Bitboard ATTACKS_WKY(uint sq) @nogc const { return _ATTACKS_WKY[(sq << 7) | computeHash(_MASK_FILE[sq])]; }
  Bitboard ATTACKS_1199(uint sq) @nogc const { return _ATTACKS_1199[(sq << 7) | computeHash(_MASK_1199[sq])]; }
  Bitboard ATTACKS_9119(uint sq) @nogc const { return _ATTACKS_9119[(sq << 7) | computeHash(_MASK_9119[sq])]; }
  Bitboard ATTACKS_RANK(uint sq) @nogc const { return _ATTACKS_RANK[(sq << 7) | computeHash(_MASK_RANK[sq])]; }
  Bitboard ATTACKS_FILE(uint sq) @nogc const { return _ATTACKS_FILE[(sq << 7) | computeHash(_MASK_FILE[sq])]; }
  Bitboard ATTACKS_HI(uint sq) @nogc const { return ATTACKS_RANK(sq) | (ATTACKS_FILE(sq)); }
  Bitboard ATTACKS_KA(uint sq) @nogc const { return ATTACKS_9119(sq) | (ATTACKS_1199(sq)); }
  alias ATTACKS_BKA = ATTACKS_KA;
  alias ATTACKS_WKA = ATTACKS_KA;
  alias ATTACKS_BHI = ATTACKS_HI;
  alias ATTACKS_WHI = ATTACKS_HI;
  Bitboard ATTACKS_pHI(uint sq) @nogc const { return ATTACKS_HI(sq) | (ATTACKS_OU[sq]); }
  Bitboard ATTACKS_pKA(uint sq) @nogc const { return ATTACKS_KA(sq) | (ATTACKS_OU[sq]); }
  alias ATTACKS_BpKA = ATTACKS_pKA;
  alias ATTACKS_WpKA = ATTACKS_pKA;
  alias ATTACKS_BpHI = ATTACKS_pHI;
  alias ATTACKS_WpHI = ATTACKS_pHI;

  // foreachを使うためのおまじない
  Range opSlice() { return Range(this); }
  struct Range {
    Bitboard bb;
    uint lastSq;
    this(Bitboard b) { bb = b; }
    @property bool empty() {
      return !cast(bool)bb;
    }
    @property uint front() {
      return lastSq = bb.lsb;
    }
    void popFront() { bb ^= MASK_SQ[lastSq]; }
  }
}

//空っぽ
immutable NULLBITBOARD = Bitboard(0, 0);

//特定の段のマスク
immutable MASK_1 = Bitboard(0x1FFUL, 0);
immutable MASK_2 = Bitboard(0x3FE00UL, 0x1UL);
immutable MASK_3 = Bitboard(0x7FC0000UL, 0x3FEUL);
immutable MASK_4 = Bitboard(0xFF8000000UL, 0x7FC00UL);
immutable MASK_5 = Bitboard(0x1FF000000000UL, 0xFF80000UL);
immutable MASK_6 = Bitboard(0x3FE00000000000UL, 0x1FF0000000UL);
immutable MASK_7 = Bitboard(0x7FC0000000000000UL, 0x3FE000000000UL);
immutable MASK_8 = Bitboard(0x8000000000000000UL, 0x7FC00000000000UL);
immutable MASK_9 = Bitboard(0, 0xFF80000000000000UL);

//特定の段から段までのマスク
immutable MASK_12 = Bitboard(0x3FFFFUL, 0x1UL);
immutable MASK_13 = Bitboard(0x7FFFFFFUL, 0x3FFUL);
immutable MASK_14 = Bitboard(0xFFFFFFFFFUL, 0x7FFFFUL);
immutable MASK_15 = Bitboard(0x1FFFFFFFFFFFUL, 0xFFFFFFFUL);
immutable MASK_16 = Bitboard(0x3FFFFFFFFFFFFFUL, 0x1FFFFFFFFFUL);
immutable MASK_17 = Bitboard(0x7FFFFFFFFFFFFFFFUL, 0x3FFFFFFFFFFFUL);
immutable MASK_18 = Bitboard(0xFFFFFFFFFFFFFFFFUL, 0x7FFFFFFFFFFFFFUL);

immutable MASK_19 = NULLBITBOARD.not();

immutable MASK_29 = MASK_1.not();
immutable MASK_39 = MASK_12.not();
immutable MASK_49 = MASK_13.not();
immutable MASK_59 = MASK_14.not();
immutable MASK_69 = MASK_15.not();
immutable MASK_79 = MASK_16.not();
immutable MASK_89 = MASK_17.not();

//着手禁止点を除いた移動先
alias MASK_LEGAL_BFU = MASK_29;
alias MASK_LEGAL_BKY = MASK_29;
alias MASK_LEGAL_BKE = MASK_39;
alias MASK_LEGAL_WFU = MASK_18;
alias MASK_LEGAL_WKY = MASK_18;
alias MASK_LEGAL_WKE = MASK_17;

alias MASK_PROMOTE_B = MASK_13;
alias MASK_PROMOTE_W = MASK_79;

alias MASK_BFU = MASK_14;  //歩が成れる移動元
alias MASK_WFU = MASK_69;
alias MASK_BKE = MASK_15;  //桂馬が成れる移動元
alias MASK_WKE = MASK_59;
alias MASK_BGI = MASK_14;  //銀が成れる移動元/移動先
alias MASK_WGI = MASK_69;
alias MASK_B = MASK_59;  //歩、桂馬の不成の移動元
alias MASK_W = MASK_15;
alias MASK_BKY = MASK_39;  //香車の不成の移動先
alias MASK_WKY = MASK_17;
alias MASK_BKA = MASK_49;  //角の不成の移動先
alias MASK_WKA = MASK_16;
alias MASK_BHI = MASK_49;  //飛車の不成の移動先
alias MASK_WHI = MASK_16;

Bitboard[81] expand(Bitboard base40, int delegate(int, int) dg1, int delegate(int, int) dg2, const ulong msk_b0 = ulong.max,
                    const ulong msk_b1 = ulong.max) {
  // base40を左右にずらした時にビットが折り返されないようにするマスク
  //ここの書き方はセコい。。
  mixin({
    string str = "Bitboard[17] _MASK_SHIFT = [";
    foreach (i; 0..17) {
      char[9] s = "000000000";
      foreach (j; 0..min(i + 1, 9)) { s[j] = '1'; }
      foreach (j; 0..i - 8) { s[j] = '0'; }
      str ~= "Bitboard(0b" ~s[8] ~s ~s ~s ~s ~s ~s ~s ~",0b" ~s ~s ~s ~s ~s ~s ~s ~s[0] ~"),";
    }
    return str ~"];";
  }());
  Bitboard* MASK_SHIFT = &_MASK_SHIFT[8];

  Bitboard[81] list;
  auto SIGNED_LEFT_SHIFT(const ulong a, const int shift) { return (shift >= 0) ? (a << shift) : (a >> (-shift)); }
  // sq==40(５五)の形を基準に各マスの場合に展開していく
  foreach (i; - 4..5)
    foreach (j; - 4..5)
      list[40 + 9 * i + j] = Bitboard(SIGNED_LEFT_SHIFT(base40.b[0], dg1(i, j)) & MASK_SHIFT[dg2(i, j)].b[0],
                                      SIGNED_LEFT_SHIFT(base40.b[1], dg1(i, j)) & MASK_SHIFT[dg2(i, j)].b[1]);
  //冗長な部分が一致するようにOR代入
  foreach (i; 0..81) {
    list[i].b[0] |= list[i].b[1] << 17;
    list[i].b[1] |= list[i].b[0] >> 17;
  }
  //非冗長化など特殊な処理を最後に実施
  foreach (i; 0..81) {
    list[i].b[0] &= msk_b0;
    list[i].b[1] &= msk_b1;
  }

  return list;
}
///駒の利きの展開
Bitboard[81] expandAttacks(Bitboard base40) { return expand(base40, (i, j) => 9 * i + j, (i, j) => -j); }

immutable Bitboard[81] MASK_SQ =
    expandAttacks(Bitboard(0b___________________0_000000000_000000000_000010000_000000000_000000000_000000000_000000000,
                           0b_000000000_000000000_000000000_000000000_000010000_000000000_000000000_0__________________));
unittest {
  foreach (i; 0..81) { assert(MASK_SQ[i].popCnt == 1, "MASK_SQ[" ~i.text ~"]: 立っているビットは1つ"); }
  foreach (i; 0..81) { assert(MASK_SQ[i].lsb == i, "MASK_SQ[" ~i.text ~"]: 配列のindexとビットの位置は等しい"); }
  foreach (i; 0..81) { assert(MASK_SQ[i] == Bitboard((1UL << i) & ((i - 64L) >> 63), (1UL << (i - 17)) & ~((i - 17L) >> 63))); }
}

immutable Bitboard[81] _MASK_1199 =
    expand(Bitboard(0b___________________0_001000000_000100000_000010000_000001000_000000100_000000010_000000001,
                    0b_100000000_010000000_001000000_000100000_000010000_000001000_000000100_0__________________),
           (i, j) { return -i + j; }, (i, j) { return i - j; }, 0xFE7F3F9FCFEUL & ~0xC06030180C0603FFUL,
           0x7F3F9FCFE0000000UL & ~0xFFC06030180C0603UL);
immutable Bitboard[81] _MASK_9119 =
    expand(Bitboard(0b___________________0_000000100_000001000_000010000_000100000_001000000_010000000_100000000,
                    0b_000000001_000000010_000000100_000001000_000010000_000100000_001000000_0__________________),
           (i, j) { return i + j; }, (i, j) { return -i - j; }, 0xFE7F3F9FCFEUL & ~0xC06030180C0603FFUL,
           0x7F3F9FCFE0000000UL & ~0xFFC06030180C0603UL);
immutable Bitboard[81] _MASK_FILE =
    expand(Bitboard(0b___________________0_000010000_000010000_000010000_000010000_000010000_000010000_000010000,
                    0b_000010000_000010000_000010000_000010000_000010000_000010000_000010000_0__________________),
           (i, j) { return j; }, (i, j) { return 0; }, 0xFFFFFFE00UL, 0x7FFFFFFFF80000UL);
immutable Bitboard[81] _MASK_RANK =
    expand(Bitboard(0b___________________0_000000000_000000000_111111111_000000000_000000000_000000000_000000000,
                    0b_000000000_000000000_000000000_000000000_111111111_000000000_000000000_0__________________),
           (i, j) { return 9 * i; }, (i, j) { return 0; }, 0xFE7F3F9FCFEUL, 0x7F3F9FCFE0000000UL);

//駒の利き
immutable Bitboard[81] ATTACKS_BFU =
    expandAttacks(Bitboard(0b___________________0_000000000_000000000_000000000_000010000_000000000_000000000_000000000,
                           0b_000000000_000000000_000000000_000000000_000000000_000010000_000000000_0__________________));
immutable Bitboard[81] ATTACKS_WFU =
    expandAttacks(Bitboard(0b___________________0_000000000_000010000_000000000_000000000_000000000_000000000_000000000,
                           0b_000000000_000000000_000000000_000010000_000000000_000000000_000000000_0__________________));
immutable Bitboard[81] ATTACKS_BKE =
    expandAttacks(Bitboard(0b___________________0_000000000_000000000_000000000_000000000_000101000_000000000_000000000,
                           0b_000000000_000000000_000000000_000000000_000000000_000000000_000101000_0__________________));
immutable Bitboard[81] ATTACKS_WKE =
    expandAttacks(Bitboard(0b___________________0_000101000_000000000_000000000_000000000_000000000_000000000_000000000,
                           0b_000000000_000000000_000101000_000000000_000000000_000000000_000000000_0__________________));
immutable Bitboard[81] ATTACKS_BGI =
    expandAttacks(Bitboard(0b___________________0_000000000_000101000_000000000_000111000_000000000_000000000_000000000,
                           0b_000000000_000000000_000000000_000101000_000000000_000111000_000000000_0__________________));
immutable Bitboard[81] ATTACKS_WGI =
    expandAttacks(Bitboard(0b___________________0_000000000_000111000_000000000_000101000_000000000_000000000_000000000,
                           0b_000000000_000000000_000000000_000111000_000000000_000101000_000000000_0__________________));
immutable Bitboard[81] ATTACKS_BKI =
    expandAttacks(Bitboard(0b___________________0_000000000_000010000_000101000_000111000_000000000_000000000_000000000,
                           0b_000000000_000000000_000000000_000010000_000101000_000111000_000000000_0__________________));
immutable Bitboard[81] ATTACKS_WKI =
    expandAttacks(Bitboard(0b___________________0_000000000_000111000_000101000_000010000_000000000_000000000_000000000,
                           0b_000000000_000000000_000000000_000111000_000101000_000010000_000000000_0__________________));
immutable Bitboard[81] ATTACKS_OU =
    expandAttacks(Bitboard(0b___________________0_000000000_000111000_000101000_000111000_000000000_000000000_000000000,
                           0b_000000000_000000000_000000000_000111000_000101000_000111000_000000000_0__________________));
alias ATTACKS_BOU = ATTACKS_OU;
alias ATTACKS_WOU = ATTACKS_OU;

//成り駒の定数名は文字列mixinのためにpXXで統一する
mixin(q{ alias ATTACKS_YYpXX = ATTACKS_YYKI; }.generateReplace("XX", [ "FU", "KY", "KE", "GI" ]).generateReplace("YY", [ "B", "W" ]));

//飛び駒の利きリストを生成する
Bitboard[81 * 128] genLongTable(int delegate(int, int) getSq, int delegate(int) getPos, int delegate(int, int) choice,
                                const Bitboard[] MASK) {
  Bitboard[81 * 128] list = new Bitboard[81 * 128];

  // occupiedのパターンのとき、pos位置の駒の飛び利きパターンを返す
  int genAttacksLine(const int occupied, const int pos, int delegate(int, int)choice) {
    int a = 0;
    for (int s = pos - 1; s >= 0 && !(a & occupied); s--) a |= 1 << s;
    int b = 0;
    for (int s = pos + 1; s < 9 && !(b & occupied); s++) b |= 1 << s;
    return choice(a, b);  //香車以外は return a | b;
  }

  // lineのパターンのビットボードを返す
  Bitboard gen(const uint line, const uint sq) {
    Bitboard bb = NULLBITBOARD;
    foreach (uint n; 0..9) {
      if (line & (1 << n)) {
        uint lineSq = getSq(sq, n);
        if (0 <= lineSq && lineSq < 81) {
          bb.b[0] |= MASK_SQ[lineSq].b[0];
          bb.b[1] |= MASK_SQ[lineSq].b[1];
        }
      }
    }
    return bb;
  }

  //直線上に並ぶ駒の配置(2^7=128パターン)別で飛び利きを初期化
  foreach (uint occupied; 0..128) {
    foreach (uint sq; 0..81) {
      //駒の配置パターンをビットボードに落とし込みhashを算出
      int occupied_line = occupied << 1;
      Bitboard hashBB = gen(occupied_line, sq);
      ulong hash = hashBB.computeHash(MASK[sq]);

      //駒の配置に対する利きを生成
      int attacks_line = genAttacksLine(occupied_line, getPos(sq), choice);
      Bitboard attackBB = gen(attacks_line, sq);
      list[(sq << 7) | hash] = attackBB;
    }
  }
  return list;
}

//各飛び駒の利きテーブル(インデックスは sq * 128 + pattern)
immutable Bitboard[81 * 128] _ATTACKS_BKY = genLongTable((sq, n) => n * 9 + sq % 9, sq => sq / 9, (a, b) => a, _MASK_FILE);
immutable Bitboard[81 * 128] _ATTACKS_WKY = genLongTable((sq, n) => n * 9 + sq % 9, sq => sq / 9, (a, b) => b, _MASK_FILE);
immutable Bitboard[81 * 128] _ATTACKS_1199 = genLongTable((sq, n) => sq - 10 * (sq % 9 - n), sq => sq % 9, (a, b) => a | b, _MASK_1199);
immutable Bitboard[81 * 128] _ATTACKS_9119 = genLongTable((sq, n) => sq + 8 * (sq % 9 - n), sq => sq % 9, (a, b) => a | b, _MASK_9119);
immutable Bitboard[81 * 128] _ATTACKS_FILE = genLongTable((sq, n) => n * 9 + sq % 9, sq => sq / 9, (a, b) => a | b, _MASK_FILE);
immutable Bitboard[81 * 128] _ATTACKS_RANK = genLongTable((sq, n) => sq / 9 * 9 + n, sq => sq % 9, (a, b) => a | b, _MASK_RANK);
