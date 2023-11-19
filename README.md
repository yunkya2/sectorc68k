# SectorC68k

SectorC68k is a C compiler written in M68000 assembly that fits within the 512 byte sector of SHARP X68000. It supports a
subset of C that is large enough to write real and interesting programs. It is quite likely the 2nd smallest C compiler ever written.

This program is derived from SectorC written by xorvoid.

----
「x86の512バイトのブートセクタに収まるCコンパイラ」 SectorC
* https://github.com/xorvoid/sectorc
* https://xorvoid.com/sectorc.html

これを 68000 MPU に移植して、X68000 で動作するようにしたものです。

~~68000の命令は16ビット単位でx86に比べるとコードサイズが大きくなるため、さすがに512バイトには収まりませんでしたが、X68000のフロッピーディスクは1024バイト/セクタなので依然として1セクタには収まっています。:-)~~

68000でも512バイトぎりぎりに収めることができました!


## サンプルコード

- `examples/hello.c:` Hello worldを表示
- `examples/count.c:` 0～99の数字を表示
- `examples/sinwave.c:` サインカーブを描画

バッチファイル `run.bat` を用いて、`run examples\hello.c` のように実行できます。

## 言語仕様

詳細は[こちら](https://github.com/xorvoid/sectorc#grammar) に書かれています。

* 変数は16bit int、グローバル変数のみです。文字定数や文字列は扱えません
* 関数は引数も戻り値も取ることができません
* 演算子は `+`,`-`,`*`,`&`,`|`,`^`,`<<`,`>>`,`==`,`!=`,`<`,`>`,`<=`,`>=` が使用できますが、演算子ごとの優先順位はありません。式を括弧で囲うことはできます
* `*(int*)`を付けると変数をポインタとして扱えますが、ポインタが指せるのはあらかじめ用意してある64kBの変数領域内のみです
* 制御命令は`if()`と`while()`のみです。`asm`文で16bitのm68k命令を直接埋め込むことができます
* オリジナルのSectorCから、16進定数を扱えるように拡張してあります
