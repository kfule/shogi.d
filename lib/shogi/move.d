module shogi.move;

struct Move {
  int _m;
  bool opEquals(const Move m) @nogc const { return (this._m & 65535U) == (m._m & 65535U); }
  this(uint from, uint to, bool promote) @nogc { _m = ((cast(int)promote) << 15) | (from << 8) | to; }
  this(uint koma, uint to) @nogc { _m = (koma << 8) | (1 << 7) | to; }

  uint getFrom() @nogc const { return (_m >> 8) & 127; }
  alias getDropPiece = getFrom;
  uint getTo() @nogc const { return _m & 127; }
  bool isPromote() @nogc const { return cast(bool)(_m & (1 << 15)); }
  bool isDrop() @nogc const { return cast(bool)(_m & (1 << 7)); }

  void setUndoInfo(uint k, uint c) @nogc { _m = (_m & 65535) | (k << 16) | (c << 24); }

  uint getMovePiece() @nogc const { return (_m >> 16) & 31; }
  uint getMovePieceWithIsPromote() @nogc const { return (_m >> 15) & 63; }
  uint getCapture() @nogc const { return (_m >> 24) & 31; }

  unittest {
    import shogi.constants;
    auto m = Move(40, 50, true);
    assert(!m.isDrop);
    assert(m.getFrom == 40);
    assert(m.getTo == 50);
    assert(m.isPromote);
    m.setUndoInfo(komaType.BFU, komaType.WFU);
    assert(m.getMovePiece == komaType.BFU);
    assert(m.getMovePieceWithIsPromote == komaTypeWP.BFUp);
    assert(m.getCapture == komaType.WFU);

    m = Move(4, 50);
    assert(m.isDrop);
    assert(m.getDropPiece == 4);
    assert(m.getTo == 50);
    assert(!m.isPromote);
  }
}
