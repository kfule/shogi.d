//各マスの長い利きの有無
struct kikiLong {
  ushort b;
  alias b this;

  ushort getB() const @nogc { return b & 255U; }
  ushort getW() const @nogc { return (b >> 8) & 255U; }

  // XORなのでremは不要
  void add(in uint direction) @nogc { b ^= 1 << direction; };
  void addB(in uint direction) @nogc { b ^= 1 << direction; };
  void addW(in uint direction) @nogc { b ^= (1 << 8) << direction; };
};

struct kikiBB {
  Bitboard[4] bb;

  Bitboard gt0() const @nogc { return bb[0] | bb[1] | bb[2] | bb[3]; }
  Bitboard gt1() const @nogc { return bb[1] | bb[2] | bb[3]; }
  Bitboard eq1() const @nogc { return bb[0] & ~bb[1] & ~bb[2] & ~bb[3]; }
  Bitboard eq2() const @nogc { return bb[1] & ~bb[0] & ~bb[2] & ~bb[3]; }
  alias ge1 = gt0;
  alias ge2 = gt1;

  void add(const Bitboard a) @nogc {
    bb[3] ^= a & bb[0] & bb[1] & bb[2];
    bb[2] ^= a & bb[0] & bb[1];
    bb[1] ^= a & bb[0];
    bb[0] ^= a;
  }
  void rem(const Bitboard a) @nogc {
    bb[3] ^= a & ~bb[0] & ~bb[1] & ~bb[2];
    bb[2] ^= a & ~bb[0] & ~bb[1];
    bb[1] ^= a & ~bb[0];
    bb[0] ^= a;
  }
  alias add_do = add;
  alias rem_do = rem;
  alias add_undo = rem;
  alias rem_undo = add;

  void print() {
    uint num(uint sq) const {
      return ((bb[3] & MASK_SQ[sq]) ? 8 : 0) + ((bb[2] & MASK_SQ[sq]) ? 4 : 0) + ((bb[1] & MASK_SQ[sq]) ? 2 : 0) +
             ((bb[0] & MASK_SQ[sq]) ? 1 : 0);
    }
    immutable wstring strY = "一二三四五六七八九";
    writeln("     ９８７６５４３２１");
    foreach (i; 0..9) {
      write("     ");
      foreach (j; 0..9) {
        uint n = num(9 * i + 8 - j);
        if (n > 2) write("\x1b[43m"); /* 背景色を黄色に */
        if (n > 1)
          write("\x1b[31m"); /* 前景色を赤に */
        else if (n > 0)
          write("\x1b[33m"); /* 前景色を黄色に */
        writef("%2d", n);
        write("\x1b[39m\x1b[49m"); /* 前景色,背景色を元に */
      }
      writeln(strY[i]);
    }
    writeln;
  }
};

enum Directions16 { Dir0, Dir1, Dir2, Dir3, Dir4, Dir5, Dir6, Dir7, Dir8, Dir9, Dir10, Dir11, Dir12, Dir13, Dir14, Dir15 };
immutable DIRECTIONS_BKY = ["0"];
immutable DIRECTIONS_WKY = ["4"];
mixin(q{ immutable DIRECTIONS_XX = [ "1", "3", "5", "7" ]; }.generateReplace("XX", [ "BKA", "WKA", "BpKA", "WpKA" ]));
mixin(q{ immutable DIRECTIONS_XX = [ "0", "2", "4", "6" ]; }.generateReplace("XX", [ "BHI", "WHI", "BpHI", "WpHI" ]));
