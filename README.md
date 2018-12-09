# pdumpfs-like
pdumpfs-like backup tool
========================

# Overview

pdumpfs と似たようなことができるバックアップ・ツール。

ディレクトリやファイル構造をそのまま保ったまま日付単位でバックアップします。
前日から変更のないファイルはハードリンクを使い、バックアップ先のディスク容量を肥大させずにバックアップします。
「○年○月○日現在の状態を取り戻したい」と言うときに簡単に取り戻せます。

毎日定時バックアップするのに向いています。

毎日一度だけ実行してください。

同じ日付の日に 2 回以上実行したらどうなるかは知りません。

# How backup.sh works

backup.sh を cron ジョブで毎日一度だけ実行しているとして説明します。

/backup/pdumpfs をバックアップ先に、/home をバックアップ元に指定して、2018年1月1日から毎日1度ずつ実行したとすると、次のようなディレクトリ構成でバックアップが作成されます。

`/backup/pdumpfs/2018/01/01/home`

`/backup/pdumpfs/2018/01/02/home`

`/backup/pdumpfs/2018/01/03/home`

`...`

/backup/pdumpfs 以下のディレクトリは backup.sh により自動作成されます。

`/home/takashi/hello.c`

というファイルがあったとします。backup.sh が1月1日に実行されると、次の場所にバックアップされます。これはフルバックアップです。

`/backup/pdumpfs/2018/01/01/home/takashi/hello.c`

次の日は2018年1月2日用のディレクトリにバックアップされます。

`/backup/pdumpfs/2018/01/02/home/takashi/hello.c`

このファイルは /home/takashi/hello.c の単純なコピーか、前日のバックアップ /backup/pdumpfs/2018/01/01/home/takashi/hello.c へのハードリンクです。

1月2日に backup.sh が走るまでの間にオリジナルの hello.c が変更されていれば、/backup/pdumpfs/2018/01/01/home/takashi/hello.c は1月2日現在の /home/takashi/hello.c を単純にコピーしたものとなります。

もし、オリジナルの /home/takashi/hello.c が前日から変更されていない、つまり前日と同じものであれば、backup.sh は、/backup/pdumpfs/2018/01/02/home/takashi/hello.c を前日のバックアップ /backup/pdumpfs/2018/01/01/home/takashi/hello.c へのハードリンクとして作成します。

1月3日になりました。ユーザー takashi は hello.c を hello-world.c にリネームしました。すると、1月3日にはこのようにバックアップされます。

`/backup/pdumpfs/2018/01/03/home/takashi/hello-world.c`

ここで、

`/backup/pdumpfs/2018/01/03/home/takashi/hello.c` 
（これはバックアップに存在しない）

のように、以前のファイルが残ることはありません。バックアップ時点のファイルやディレクトリ構成が再現されます。

要するに、「YYYY年MM月DD日の /home ディレクトリ以下を再現したい」と思ったら、

`/backup/pdumpfs/<YYYY>/<MM>/<DD>/home`

以下を /home 以下に書き戻せばいいのです。

もちろん「このファイルだけ取り戻したい」というときは、ファイル名を指定してバックアップからコピーしてくるということもできます。

# Warning
/backup/pdumpfs/&lt;YYYY&gt;/&lt;MM&gt;/&lt;DD&gt;/home 以下にあるファイルはハードリンクかもしれません。絶対に上書きしないでください。ハードリンクは同じ実体のファイルを指しています。

もし /home/takashi/hello.c が1月1日から半年間変更されていなかったとすると、バックアップの次の hello.c はすべて同じ実体を指しています。

`/backup/pdumpfs/2018/01/01/home/takashi/hello.c` 

`/backup/pdumpfs/2018/01/02/home/takashi/hello.c` 

`/backup/pdumpfs/2018/01/03/home/takashi/hello.c` 

`...`

`/backup/pdumpfs/2018/02/01/home/takashi/hello.c` 

`/backup/pdumpfs/2018/02/02/home/takashi/hello.c` 

`/backup/pdumpfs/2018/02/03/home/takashi/hello.c` 

`...`

`/backup/pdumpfs/2018/05/01/home/takashi/hello.c` 

`/backup/pdumpfs/2018/05/02/home/takashi/hello.c` 

`/backup/pdumpfs/2018/05/03/home/takashi/hello.c` 

`...`

`/backup/pdumpfs/2018/06/28/home/takashi/hello.c` 

`/backup/pdumpfs/2018/06/29/home/takashi/hello.c` 

`/backup/pdumpfs/2018/06/30/home/takashi/hello.c` 

`...`

もし、

`# cat /dev/null > /backup/pdumpfs/2018/02/02/home/takashi/hello.c` 

という操作をすると、上記のすべての hello.c の内容は失われます。
上記のどれか1つの hello.c を書き換えると、その変更は上記すべての hello.c に反映されます（同じ実体を参照しているのだからあたりまえですね）。

# Note
いろいろな理由で毎日1回バックアップができず、バックアップができない日があったとします。
その場合、backup.sh は過去のバックアップのうち最新のものを探してきて、それを利用します。
ですので、何日かバックアップをしていなかったからといって、フルバックアップから始めなければならないという事態にはなりません。

これには制限があり、最大100日を超えてバックアップが取られていなかったら、過去のバックアップはなかったものとして、フルバックアップから始めます。

この値はシェルスクリプト中の GIVEUP_DAYS シェル変数で変更できます。


# Installation
backup.sh が本体です。
backup.sh を適当に書き換えて /usr/local/sbin などにおいて実行します。

シェル変数

BACKUPDIR  : ここに指定したディレクトリにバックアップが保存されます。

スクリプト中で mount コマンドに与える値

MOUNTLABEL : バックアップを格納するパーティションのラベル。

MOUNTPOINT : MOUNTLABEL で指定したパーティションをマウントするマウントポイント。

FILESYSTEM : MOUNTLABEL で指定したパーティションのファイルシステム名。

MOUNTOPT   : マウントオプション

バックアップしたいディレクトリはシェル関数 backup と backup_home があります。

backup "/bin" "$PREV_BKUP_DIR" "$DEST_DIR"

のようになっているところをカスタマイズします。

# Limitation
高度なことはしていません。rsync コマンドで単純に順番にファイルをコピーしているだけです。
ある一瞬のスナップショットを取って不整合なくバックアップしたいという用途には向きません。

# Disclaimer
おかしな動作をしてファイルを失うようなことがあっても作者は責任を取れません。

# Author
Shimaden &lt;shimaden@shimaden.homelinux.net&gt;
