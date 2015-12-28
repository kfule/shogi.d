import std.random;
import std.datetime;
import std.stdio;
import std.conv;
import std.algorithm;
import std.array;
import std.regex;
import std.string;

import shogiban;
import move;
import testcode;

void main() {
  auto s = new Shogiban;
  s.init;
  s.writeln;

  //コマンド受付
  string line;
  while ({
    write(">");
    return ((line = stdin.readln()) !is null);
  }()) {
    if (line.strip() == "") line = "(null)";
    string[] args = line.split();
    switch (args[0]) {
      mixin(strCommands);  //コマンドの展開
    }
  }
}

immutable string strCaseMain = q{
  case "d":  // D言語くん
q{
 (_) (_)
/______ |
||(O(O |/
 | | | |
 | |_| |
/______/
  <   >
 (_) (_)
}.writeln;
break;
  case "init", "i":  //盤面の初期化
    s.init;
    s.writeln;
    break;
  case "print", "p":  //盤面の表示
    s.writeln;
    break;
  case "quit", "q":  //終了
    return;
  case "help":  //ヘルプ(caseの表示)
  default:
    printCaseText(args[0]);
    break;
};

//実行できるコマンドを画面に表示する
void printCaseText(string arg) {
  if (arg != "help") writeln("invalid command: " ~arg);
  writeln("\nコマンドは下記の通り");
  auto r = regex(r"(?<=case\s)\u0022.+[^\n]");
  foreach (c; matchAll(strCommands, r)) {
    writef("%-16s", replaceAll(c.hit, regex(r"\u0022|//.*|:"), ""));
    writeln(replaceAll(c.hit, regex(r".*\u0022|//[\p{WhiteSpace}]*|:"), ""));
  }
  writeln();
}

//コンパイル時にファイル内を検索してコマンドっぽい文字列変数を収集して結合する
immutable string strCommands = mixin({
  string s = "";
  auto str = import(__FILE__);
  uint cnt;
  while (!str.empty) {
    str = str.find("str" ~"Case");  //こいつ自体が検索に引っかからないように
    if (!str.empty) {
      if (cnt++) s ~= "~";
      s ~= " " ~str[0..11];  //文字列名は後ろ4文字を含めて11文字
      str = str[11.. $];
    }
  }
  return s;
}());
