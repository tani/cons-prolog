# sprolog 0.8.0 — SBCL 向け S式 Prolog

PAIP / Allegro Prolog の API に着想を得た、独立した初期実装です。
既存処理系のコードは流用していません。Franz Inc. の製品ではなく、同社との提携・承認もありません。
ライセンスは MIT です。

## 実行

外部 Lisp ライブラリは不要です。プロジェクトのディレクトリで実行します。

```sh
sbcl --script examples/append.lisp
sbcl --script examples/dcg.lisp
sbcl --script examples/slg.lisp
sbcl --dynamic-space-size 2048 --control-stack-size 1 --script tests/run.lisp
```

検証環境: SBCL 2.2.9 / Linux x86-64。
テストは100万段の末尾再帰を含みます。2 GiB はヒープの上限指定であり、使用量ではありません。

既存セッションでは以下でロードします。

```lisp
(require :asdf)
(asdf:load-asd (truename "sprolog.asd"))
(asdf:load-system "sprolog")
(use-package :sprolog)
```

## 定義と問い合わせ

```lisp
(<-- (append () ?ys ?ys))
(<- (append ( ?x  . ?xs) ?ys ( ?x  . ?zs))
    (append ?xs ?ys ?zs))
(?- (append ?xs ?ys ( a b c)))
;; => (((?xs) (?ys a b c))
;;     ((?xs a) (?ys b c))
;;     ((?xs a b) (?ys c))
;;     ((?xs a b c) (?ys)))
```

`<--` は同名・同アリティの節を置き換え、`<-` は最後に追加します。
通常の述語は左から右のゴール選択、定義順の節選択、深さ優先探索です。
テーブル化した述語は後述の SLG で評価します。
`?x` のようなシンボルは論理変数、単独の `?` は出現ごとに独立する匿名変数です。
シンボルの同一性には Common Lisp のパッケージが影響します。

初版の `?-` はすべての解を alist のリストで返します。
Allegro の対話的な表示・継続入力は未実装です。
失敗は `NIL`、変数を含まないゴールの1解は `(NIL)` です。
無限の解集合には件数制限またはカーソルを使います。

```lisp
(query '((append ?xs ?ys ( a b c))) :limit 2)
(let ((cursor (make-query '((append ?xs ?ys ( a b c))))))
  (unwind-protect
      (loop
        (multiple-value-bind (solution foundp) (next-solution cursor)
          (unless foundp (return))
          (print solution)))
    (close-query cursor)))
```

`NEXT-SOLUTION` の第2返り値で解の存在を判断します。
解の cons はコピーされ、バックトラック後も保持できます。
未束縛変数は fresh な `?G...` シンボルとなり、一つの解の中では変数の同一性を保持します。
`QUERY-STATISTICS` は命令数、最大継続深度・選択点数、累計割当セル数、現在／最大ヒープセル数、Trail と GC の統計を返します。
`MAKE-DATABASE` と `*DATABASE*` の動的束縛でデータベースを分離でき、`CLEAR-DATABASE` で消去できます。

## 項の構文

項は通常の Lisp の cons 構造です。複合項とリストを区別しません。

```lisp
(?- (= ?x (f a b)))
(?- (= ?x (a b c)))
(?- (= (a . ?tail) (a b))) ; ?tail = (b)
```

`list`／`cons` は特別な項構築構文ではなく、項位置では普通のシンボルです。
`(f)` は項位置では1要素のリスト、ゴール位置では `f/0` の呼び出しです。
入力・解・Lisp コールバックは同じ cons 表現を使い、共有・循環も扱えます。
ISO Prolog への準拠や項の翻訳は目標としません。

## Lisp との接続

```lisp
(let ((items '(a b c)) (results nil))
  (prolog
    (lisp ?items items)
    (append ?xs ?ys ?items)
    (lisp (push (list ?xs ?ys) results)))
  (nreverse results))
```

- `(lisp ?output expression)` は Lisp 式の結果を出力項と単一化します。
- `(lisp expression)` は式を評価し、返り値にかかわらず成功します。
- `(lispp expression)` は Lisp の真偽値に従います。
- `PROLOG` は全解を列挙し、通常 `NIL` を返します。
- `RETURN-FROM PROLOG` と例外では Lisp の `UNWIND-PROTECT` により VM を解放します。

ホスト式をクロージャにするため外側のレキシカル変数を参照できます。
初版では `<-` / `<--` 内のホスト式も定義時のレキシカル環境を捕捉します。
これは既存 API に対する拡張であり、完全互換を意味しません。
論理変数のホスト入力はコピーした Lisp データです。ホスト計算には ground な項を使ってください。
未束縛変数をホスト側で操作する API はありません。
ホスト式の `?` 接頭辞のシンボルは引用式中も論理変数として検出します。
Lisp の副作用はバックトラックで取り消しません。

## 対応状況

| 機能 | 初版 |
|---|---|
| 事実・規則・再帰・複数節 | 対応 |
| リスト・末尾付きリスト・複合項 | `list`／`cons`／`(f ...)` |
| `(= ?x term)` | 対応 |
| `!` / `(!)` | 述語入口を境界とするカット |
| `true` / `(true)` / `fail` / `(fail)` | 対応 |
| 末尾呼び出し | `execute` で継続フレームを再利用 |
| `prolog` / `lisp` / `lispp` | 上記の範囲で対応 |
| 節の追加・置き換え | `<-` / `<--` |
| `asserta` / `assertz` / `retract` / `call/1..8` / 選言・否定 | `src/builtins.lisp` で実装 |
| `findall` / `bagof` / 算術述語 / occurs check | `src/builtins.lisp` で実装 |
| Prolog ゴールとしての `unwind-protect` | 未実装 |
| Allegro の変数 API・対話 UI・完全互換 | 未実装 |
| X/Y レジスタ、read/write モード、細粒度の項命令 | 対応 |
| 条件付き Trail・VM GC | 対応 |
| SLG variant tabling・左再帰・相互再帰 | 対応 |
| ground な `tnot`・well-founded semantics | 対応 |
| 第一引数インデックス | 未実装 |

未定義述語は初版では失敗します。`TRUE`、`FAIL`、`!`、`=`、`PHRASE`、`TNOT` は予約名です。
原子的な項の比較は `EQL` で、文字列・任意のオブジェクトを `EQUAL` では比較しません。
単一化は occurs check のない rational-tree 方式です。循環する cons 項も扱えます。
循環する解の出力には `*PRINT-CIRCLE*` を `T` にしてください。

## VM と制約

コンパイラの標準バックエンドは、WAM の細粒度な項命令を生成します。

| 命令群 | 対応命令 |
|---|---|
| head の照合 | `get-variable`, `get-value`, `get-constant`, `get-list`, `get-structure` |
| body の構築 | `put-variable`, `put-value`, `put-constant`, `put-list`, `put-structure` |
| read/write モードの項走査 | `unify-variable`, `unify-value`, `unify-constant`, `unify-void` |
| write モードの項構築 | `set-variable`, `set-value`, `set-constant`, `set-void` |
| 環境・制御 | `allocate`, `deallocate`, `call`, `execute`, `proceed` |

`A_i` は `X_i` の別名です。節内の論理変数は Y スロット、一時的な構造項参照は X レジスタに置きます。
変数セル自体はヒープに置くため、スタック変数をヒープへ移す unsafe/local 命令は不要です。
`DISASSEMBLE-PREDICATE` で生成した命令を確認できます。

公開 API の cons ベースの項表現を維持しています。短い proper な `(functor arg ...)` は
構造項命令で、長いリスト・open list はリスト命令で処理します。双方とも同じ cons 単一化の意味を保ちます。
構造項の最大認識長はコンパイラの最適化上の制限であり、扱える項の長さやアリティの制限ではありません。
タグ付きセルを連続アドレスに配置する古典的 WAM のメモリ表現そのものではありません。
実行バックエンドは細粒度 WAM のみです。旧バックエンドとその命令ベクタは除去しました。
コンパイラ内部のテンプレート IR は、WAM 命令へ必ず変換されます。

Prolog 呼び出しは Lisp の再帰を使いません。
単一化、項のコンパイル・実体化・結果コピー・GC の到達可能性走査も明示的な作業リストで処理します。
ユーザーが呼ぶ Lisp 式自体の再帰はこの保証に含みません。

## DCG

文法規則は `-->` で追加し、`--->` で同名・同アリティの文法を置き換えます。
Prolog ゴールの `(-> 条件 成功時)` は条件の最初の解にコミットします。
`(or (-> 条件 成功時) 失敗時)` で if-then-else を表します。
この2つは本プロジェクトの S式構文です。文法の非終端には入力と残余入力の2引数を追加し、
通常の Prolog 節へ展開してから同じ WAM でコンパイル・実行します。

```lisp
(---> (article) (:terminals the))
(---> (noun cat) (:terminals cat))
(--> (noun dog) (:terminals dog))
(---> (sentence ?noun) (article) (noun ?noun))

(?- (phrase (sentence ?noun) ( the cat)))
;; => (((?noun . cat)))

(?- (phrase (sentence ?noun) ?tokens))
;; => (((?noun . cat) (?tokens the cat))
;;     ((?noun . dog) (?tokens the dog)))

(?- (phrase (sentence ?noun) ( the dog extra) ?rest))
;; => (((?noun . dog) (?rest extra)))
```

| 文法本体 | 意味 |
|---|---|
| `(noun ?x)` または `noun` | 非終端呼び出し |
| `(:terminals a b ?x)` | トークン列。論理変数・複合トークンも可能 |
| `(:terminals)`、`(:seq)`、規則の空の本体 | 空列 |
| 複数の本体形式、`(:seq A B ...)` | 連接 |
| `(:or A B ...)` | 記載順の選言。各枝が複数形式なら `:seq` で包む |
| `(:goal G)`、`(:goals G1 G2 ...)` | 入力を消費しない通常の Prolog ゴール |
| `!`、`(!)` | 現在の文法規則のカット |

`:goals` では `lisp` / `lispp` も使え、定義や問い合わせのレキシカル環境を捕捉します。

```lisp
(let ((offset 10))
  (---> (adjusted ?out)
        (:terminals ?n)
        (:goals (lispp (integerp ?n)) (lisp ?out (+ ?n offset)))))

(?- (phrase (adjusted ?out) ( 3))) ; => (((?out . 13)))
```

`PHRASE/2` は残余入力を空列に固定し、`PHRASE/3` は残余を明示します。
問い合わせの文法引数には非終端に加えて `:seq` / `:or` / `:terminals` 等の文法式を記述できます。
生成された内部変数は利用者の変数と衝突せず、解の alist にも現れません。
文法式としての `phrase` は独立したカット境界を持ち、呼び出し元の選択点を削除しません。

Lisp 関数 `PHRASE` は実行時のデータから解を収集します。引数は通常の Lisp 式です。

```lisp
(phrase '(sentence ?noun) '( the cat))
(phrase '(sentence ?noun) '?tokens nil :limit 1 :gc-threshold 64)
```

キーワード引数を使う場合は第3引数の残余も明示してください。
Lisp 式を含む文法をレキシカル環境と接続する場合は `?-` / `PROLOG` / DCG 定義マクロを使います。
ストリーミングは通常どおり `MAKE-QUERY` に `((phrase ...))` を渡して行えます。

`DCG-EXPAND` は引用した頭部と本体から、展開後の頭部・本体を2値で返します。
選言は複数の節へ配布せず、同じ環境内の `try-branch` / `jump` に変換します。
このため前段の副作用を各枝で重複実行せず、選言内のカットも文法規則の代替節を削除します。
GC は分岐の保存環境もルートとして保持します。

未対応: 変数に格納した非終端の動的呼び出し、semicontext/push-back、DCG の否定・条件分岐。
文字列リテラルの自動的な文字／コード列化は行いません。端末は明示的なトークン列です。
左再帰は通常の深さ優先 Prolog と同様に停止しない場合があります。
後述の `TABLE` 宣言を展開後のアリティで行うと、SLG で評価できます。

## SLG resolution

`(table 'name arity)` で述語を variant tabling の対象にします。宣言は節定義の前後どちらでも行えます。
`(untable 'name arity)` で通常の SLD に戻します。両関数は省略可能な第3引数にデータベースを取ります。
`CLEAR-DATABASE` は節と宣言の両方を消去します。

```lisp
(table 'path 2)
(<-- (path ?x ?y) (path ?x ?z) (edge ?z ?y)) ; 左再帰を先に置く
(<- (path ?x ?y) (edge ?x ?y))
(<-- (edge a b)) (<- (edge b c)) (<- (edge c a))
(?- (path a ?y))
;; => (((?y . b)) ((?y . c)) ((?y . a)))
```

変数名の違いを除いて同じ呼び出しはテーブルを共有し、変数の共有関係もキーに含めます。
新しい呼び出しを generator として評価し、その解を必要とする consumer の WAM 継続を保存します。
新しい解だけを各 consumer に渡して継続を再開するため、左再帰・相互再帰・根拠のない正循環を扱えます。
非 ground な解も共有関係を保ってコピーし、variant な重複解を除きます。解の包含による subsumption は行いません。

スケジューラはキューで動き、到達した呼び出し variant 間の正・負の依存を記録します。
動的な強連結成分（SCC）を反復的なグラフ走査で計算し、外向きの未完成依存と未処理の仕事がない成分から完成させます。
SCC 間の呼び出しは子の完成を待ち、同一 SCC 内の再帰呼び出しは consumer として中断・再開します。
否定も SCC 間では完成を待ち、否定循環では遅延と簡約を行います。
freeze register によるスタック共有ではなく、継続と束縛グラフをコピーする実装です。
そのため suspended consumer が多い探索ではメモリ使用量が大きくなります。
通常の深さ優先探索と解の順序が異なることがあります。

### 遅延否定と truth values

`(tnot (p ...))` は well-founded negation です。対象は宣言済みの tabled 述語で、
選択された時点の引数が ground である必要があります。非 ground な否定は floundering としてエラーにします。
評価中の否定を遅延リストへ移し、真の解が得られた対象の否定を失敗させ、
解を持たない対象の否定を成功へ簡約します。残る否定循環は `:undefined` です。

```lisp
(table 'p 0) (table 'q 0)
(<-- (p) (tnot (q)))
(<-- (q) (tnot (p)))
(query '((p)) :truth-values t)
;; => ((:truth :undefined :bindings nil :delays ((q))))
```

`QUERY` / `?-` は既定では真の解のみを列挙します。`QUERY :truth-values t` は
各解を `(:truth :true-or-undefined :bindings alist :delays goals)` として返します。
`:delays` 内の各ゴールは、その否定が未決定であることを表します。
同じ束縛に対する異なる条件付き導出は、異なる遅延リストを持つ複数の解として返る場合があります。
真の導出が存在する束縛については、その条件付き variant を除去します。
偽のゴールは解を返しません。

`NEXT-SOLUTION` は第1・第2返り値に加え、第3返り値に `:true` / `:undefined`、
第4返り値に遅延リストを返します。第2返り値は条件付き解についても `T` です。

### DCG と制約

```lisp
(table 'letters 2) ; 元の引数が0個なら展開後は2個
(---> (letters) (letters) (:terminals a))
(--> (letters))
(?- (phrase (letters) ( a a a))) ; => (NIL)
```

- テーブル空間は問い合わせごとに独立し、`CLOSE-QUERY` または列挙終了で解放します。
- `QUERY-STATISTICS` の `:slg` にテーブル数・解数・中断／再開数・継続コピー数・worker 命令数を返します。
  `:completed-components` は完成した SCC 数、`:max-component-size` は完成した SCC の最大テーブル数、
  `:local-waits` は未完成の子呼び出しを待った累計回数です。
  従来のヒープ／命令統計は外側の VM の値で、SLG 全体の使用バイト数ではありません。
- 各 worker・保存継続は独立した項グラフを所有します。実行中の worker は従来の VM GC を使い、
  保存継続は Lisp GC のルートとして保持されます。
- SLG 内の cut は以下の制約で対応します。Lisp callback は generator 内および条件付き解の後では未対応で、エラーにします。
  完成した真の解を受け取る通常の呼び出し元では callback を使用できます。
- 循環項を含むテーブルキー・解は未対応で、エラーにします。通常の SLD の rational-tree 単一化は維持します。
- テーブルを開始したカーソルの途中で節や宣言を変更した場合は、次の実行でエラーにします。新しい問い合わせを開始してください。
- 有限個の呼び出し variant・解と、停止する untabled 部分を持つ探索が対象です。
  項の大きさが無限に増える規則や untabled な左再帰は停止を保証しません。
- call/answer subsumption、answer aggregation、非 ground 否定、incremental tabling、ground な成功による即時完成は未対応です。

### SLG と cut

cut は XSB 型の実行時制約で扱います。通常の選択点と完成済みテーブルの解の列挙は剪定できます。
未完成の tabled 呼び出しを跨ぐ場合は、`SLG-INCOMPLETE-CUT` condition を送出します。
判定は実際に到達した呼び出しと、その時点の SCC／完成状態に依存します。

```lisp
(table 'first-path 1)
(<-- (first-path ?x) (path a ?x) !)
(?- (first-path ?x)) ; PATH の SCC が完成してから1解を選ぶ
```

この cut は呼び出し元の代替節・解の列挙を剪定します。完成した `PATH` テーブルの他の解は保持します。
テーブル述語の節入口の cut や、通常の非テーブル helper 内だけを剪定する cut も使えます。
DCG の述語 cut と `PHRASE` の独立した cut 境界も保持します。

```lisp
(table 'bad 1)
(<-- (bad ?x) (bad ?x) !)
(<- (bad base))
(?- (bad ?x)) ; SLG-INCOMPLETE-CUT: 同じ未完成 SCC の呼び出しを剪定する
```

保存継続には元の cut 境界の識別子を保持し、コピー時の物理的な選択点位置を補正します。
再開後の cut、helper から戻った後の cut、別の節で実行される cut についても、
まだ生きている suspended alternative を含めて検査します。
`SLG-INCOMPLETE-CUT` は問い合わせを中止し、部分的なテーブルを解放します。
`NEXT-SOLUTION` でこのエラーを捕捉しても、同じカーソルから列挙を再開することはできません。
新しい問い合わせを開始してください。実行中の他のエラーもカーソルを中止します。

設計の参考: [XSB Programmer's Manual, Using Tabling](https://xsb.sourceforge.net/manual1/manual1.pdf)。
XSB のコードを利用した実装ではありません。

## VM の GC

変数セルと VM が構築した cons セルを管理し、nonmoving な mark/compact を行います。
オブジェクトの同一性を保ちながら所有ベクタを圧縮し、実際のバイト領域の回収は SBCL の GC に委ねます。
外部 Lisp オブジェクトは、到達可能性走査で cons をたどりますが、割当セル数には含めません。

ルートは現在の X/A・Y、保存した継続の Y、全選択点の引数・分岐環境・継続、問い合わせの名前付き変数、
実行中の項走査の位置、SLG generator の解を収集する引数です。循環項にも対応します。
Trail は通常のルートとしてすべてを保持するのではなく、到達可能な変数の必要な undo 記録のみを残します。
ヒープと Trail の圧縮後には、各選択点の復元マークを残存セル数へ写し直します。
変数の割当時刻は単調増加する独立の番号で保持し、GC 後も条件付き Trail の新旧判定を変えません。

自動回収は呼び出し／復帰および一時レジスタ消去の安全な命令境界で行います。
既定の開始閾値は 4,096 セルです。生存セル数が大きいときは閾値を適応的に増やし、毎命令の全走査を避けます。
回収後には所有ベクタの容量も縮めます。

```lisp
(let ((cursor (make-query '((append ?xs ?ys ( a b c))) :gc-threshold 64)))
  (unwind-protect
      (progn
        (next-solution cursor)
        (collect-query-garbage cursor) ; 手動回収も可能
        (query-statistics cursor))
    (close-query cursor)))

;; NIL は自動回収を無効にする。
(query '((append ?xs ?ys ( a b c))) :gc-threshold nil)
```

GC が抑えるのは不要になった項の保持です。探索に必要な選択点・非末尾継続・出力項が大きくなる場合、
生存メモリも増えます。解をすべて保存する `QUERY` の結果や、コンパイル済みコードはこのヒープ統計の対象外です。
`CLOSE-QUERY` または解の列挙終了で VM のルートと所有ベクタを解放します。

節の更新は新しい命令ベクタを公開します。開始済み呼び出しの代替節は旧ベクタに残り、
新しい呼び出しは更新後の定義を使います。組み込みの assert/retract も同じ logical update view を使います。
静的・動的述語の完全なディレクティブ分類は未対応です。
同期機構は未実装なのでデータベースは単一スレッドで使います。

## 組み込み述語

`src/builtins.lisp` に101個の基本述語 indicator と7個の別名を実装しています。
単一化は `=`、非単一化可能性の検査は `/=`、項の同一性は `==`／`/==`、
算術比較は `===`／`=/=` です。制御には `and`、`or`、`/+`、`->` を使えます。
ビット演算には `logand`／`logior`／`lognot` を使います。

ISO の関手・引数操作、標準項順序、`sort`／`keysort`／`setof` は削除しました。
Prolog テキストの解析・出力・演算子宣言も削除しました。
`bagof` はグループを最初の出現順に返します。未定義述語はデフォルトで
existence error になり、`unknown` フラグで失敗へ変更できます。

詳細は [BUILTINS.md](BUILTINS.md) を参照してください。
