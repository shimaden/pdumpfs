#!/bin/bash
# http://x68000.q-e-d.net/~68user/unix/pickup?rsync
# http://tech.nitoyon.com/ja/blog/2013/03/26/rsync-include-exclude/

# 例
#
# 1. 同じディレクトリ階層内の判断
#
# 　MP3 だけをコピーするには --include と --exclude を次の順に指定する。
#
#   rsync -av --include='*/' --include='*.mp3' --exclude='*' src dst
#
#     --include='*/'   : ディレクトリをコピーする
#     --include='*.mp3': 拡張子が MP3 のファイルはコピーする
#     --exclude='*'    : それ以外はコピーしない
#
# もし、exclude を手前にもってきて、
#
#   rsync --include='*/' --exclude='*' --include='*.mp3' src dst
#
# とすると、
#
#     --include='*/'   : ディレクトリーをコピーする
#     --exclude='*'    : すべてのファイルをコピーしない
#     --include='*.mp3': 拡張子が MP3 のファイルはコピーする
#
# となり、*.mp3 の前に * にマッチしてしまうので、何もコピーしてくれない。
#
# 　フィルターの指定順には意味があって、先頭から順番に判定していくと覚えておこう。
#
#
# 2. ディレクトリ階層の異なる対象のコピーの判断
#
# 　以下の指定では、src/ ディレクトリ以下にある public_html/index.html は
# コピーされない。
#
#   rsync -av --include='index.html' --exclude='public_html/' src dst
#
# 　rsync は public_html/index.html をコピーするか判定する前に、上の階層の
# public_html をコピーするかどうかを確認する。
# 　だからまず public_html ディレクトリに対して、フィルタを順に適用する。
#
#     --include='index.html'  : は public_html にはマッチしない
#     --exclude='public_html/': 次にこれがチェックされ、これはマッチする
#
# rsync は --exclude にマッチしたディレクトリ配下はチェックしないので、
# この public_html/index.html はコピーされない。

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
export PATH

# 二重起動チェック
function is_doubly_executed()
{
  local cmdline="$(cat /proc/$$/cmdline | xargs --null)"
  if [[ $$ -ne $(pgrep -oxf "$cmdline") ]]; then
    return 0
  fi
  return 1
}

# BACKUP_TEST を定義するとテストモード。

if [ "${BACKUP_TEST-UNDEF}" = "UNDEF" ]; then
  RSYNC=/usr/bin/rsync
  MOUNT=/bin/mount
  UMOUNT=/bin/umount
  LOGDIR=/var/log/pdumpfs
else
  RSYNC="echo /usr/bin/rsync"
  MOUNT="echo /bin/mount"
  UMOUNT="echo /bin/umount"
  LOGDIR=./log
fi

function usage()
{
  echo "$(basename "$0") [--dry-run]" 1>&2
}

case $# in
  0)
    DRY_RUN=
    ;;
  1)
    if [ "$1" = "--dry-run" ]; then
      DRY_RUN='--dry-run'
    else
      usage
      exit 1
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac

# The backup is restored under this directory.
BACKUPDIR=/backup/pdumpfs

if [ -z "$DRY_RUN" ]; then
  LOG="$LOGDIR/pdumpfs.log"
  ERRLOG="$LOGDIR/pdumpfs-err.log"
else
  LOG="/dev/null"
  ERRLOG="/dev/null"
fi

DATE_FMT="+%Y-%m-%d %a %T (%Z)"

# The label of the partition that you want your backup to be stored.
MOUNTLABEL=backup
# The mount point for the partition to store backup.
MOUNTPOINT=/backup
# The filesystem of the partition.
FILESYSTEM=ext4
# Mount options.
MOUNTOPT="rw"

GIVEUP_DAYS=100

if is_doubly_executed; then
  echo "Backup already running. Exit." | tee -a "$LOG" >> "$ERRLOG"
  exit 1
fi

# ----- Begin before and after process -----

# Mount and unmount the partition to store the backup. Backup.sh:
#
#   1. Mount the partition that the files you want to back up are stored.
#   2. Make a backup of the specified directory on the partition.
#   3. Unmount the partition.
#
# The partition is specified by the shell variable MOUNTLABEL.
# You may modify the line beginning with "$MOUNT LABEL=..." for your system.

# Called before starting to backup.
before_backup()
{
  if [ -n "$DRY_RUN" ]; then
    return 0
  fi
  $MOUNT LABEL="$MOUNTLABEL" -t "$FILESYSTEM" -o "$MOUNTOPT" "$MOUNTPOINT" >> "$LOG" 2>> "$ERRLOG"
  return $?
}

# Called after backup has finished.
#
after_backup()
{
  if [ -n "$DRY_RUN" ]; then
    return 0
  fi
  $UMOUNT "$MOUNTPOINT" >> "$LOG" 2>> "$ERRLOG"
  return $?
}

# ----- Signal handler -----
signal_handler()
{
  local sygname="$1"
  echo "$sygname received." | tee -a "$LOG" >> "$ERRLOG"
  local child_proc="$(jobs -p)"
  if [ -n "$child_proc" ]; then
    echo "Try killing processes: $child_proc" | tee -a "$LOG" >> "$ERRLOG"
    echo "kill -SIGINT $child_proc" | tee -a "$LOG" >> "$ERRLOG"
    kill -SIGINT $child_proc >> "$LOG" 2>> "$ERRLOG"
    echo "kill exitted with status $?" | tee -a "$LOG" >> "$ERRLOG"
  else
    echo "No processes to kill." | tee -a "$LOG" >> "$ERRLOG"
  fi
  (LC_ALL=C ; df "$MOUNTPOINT")
  after_backup
  (LC_ALL=C ; echo "[$(date "$DATE_FMT")]: $sygname: Backup terminated.") | tee -a "$LOG"
  exit 1
}

trap "signal_handler SIGINT"  SIGINT
trap "signal_handler SIGTERM" SIGTERM
trap "signal_handler SIGQUIT" SIGQUIT

# ----- Utility -----
function today_date()
{
  local days_ago="$1"
  if [ -z "$days_ago" ]; then
    date +"%Y/%m/%d"
  else
    date +"%Y/%m/%d" --date="$days_ago days ago"
  fi
}

function dest_dir()
{
  echo "$BACKUPDIR/$(today_date)"
}

function prev_backup_dir()
{
  local directory=
  local found=
  for((i = 1 ; i <= $GIVEUP_DAYS ; ++i))
  {
    directory="$BACKUPDIR/$(today_date $i)"
    if [ -d "$directory" ]; then
      echo "$directory"
      found=yes
      break
    fi
  }
  if [ "$found" != "yes" ]; then
    echo "nil"
  fi
}

# ------------------------------------------

function backup()
{
  local dir="$1"
  local prev_day_bkup_dir="$2"
  local today_dest_dir="$3"
  $RSYNC $DRY_RUN -v -aHAX --partial --delete \
        --exclude '/boot/lost+found/' \
        --exclude '/home/lost+found/' \
        --exclude '/usr/lost+found/' \
        --exclude '/usr/local/lost+found/' \
        --exclude '/var/lost+found/' \
        --exclude '/var/cache/apt/archives/' \
        --exclude '/var/fileserver/lost+found/' \
        --exclude '/var/hdd2gb/' \
        --link-dest="$prev_day_bkup_dir" \
                    "$dir" "$today_dest_dir" >> ${LOG} 2>> ${ERRLOG}
}

function backup_home()
{
  local dir="$1"
  local prev_day_bkup_dir="$2"
  local today_dest_dir="$3"
  $RSYNC $DRY_RUN -v -aHAX --partial --delete \
        --exclude '*.mp4'   \
        --exclude '*.wav' \
        --exclude '/home/lost+found/' \
        --link-dest="$prev_day_bkup_dir" \
                    "$dir" "$today_dest_dir" >> ${LOG} 2>> ${ERRLOG}
}

# ====================
# =   Main Routine   =
# ====================

before_backup

if [ $? -eq 32 ]; then
  echo "Mount failed. Assume the partition already mounted. Continue to backup..."
fi

(LC_ALL=C ; echo "[$(date "$DATE_FMT")]: Backup started.") | tee -a "$LOG"

DEST_DIR="$(dest_dir)"
PREV_BKUP_DIR="$(prev_backup_dir)"

if [ -z "$DRY_RUN" ]; then
  if [ "$PREV_BKUP_DIR" = "nil" ]; then
    echo "Implement first backup feature." 1>&2
    exit 1
  fi
fi

if [ ! -d "$DEST_DIR" ]; then
  echo "No such directory: $DEST_DIR . It will be created." | tee -a "$LOG" | tee -a "$ERRLOG"
  new_month_dir="$(echo "$DEST_DIR" | sed -re 's/\/[0-9][0-9]\/*$//')"
  echo "new_month_dir: $new_month_dir"
  if [ ! -d "$new_month_dir" ]; then
    echo "Create new_month_dir: $new_month_dir"
    mkdir -m 700 -p "$new_month_dir"
  fi
fi

#=======================
# Custumize from here...
#=======================

# Shell functions:
# backup <dir-to-be-backed-up> "$PREV_BKUP_DIR" "$DEST_DIR"
# backup_home <dir-to-be-backed-up> "$PREV_BKUP_DIR" "$DEST_DIR"

# backup_home is an alternative version of backup.
# Two shell variables PREV_BKUP_DIR and DEST_DIR have been suitably set 
# by the above code. No need to modify them.

backup "/bin"       "$PREV_BKUP_DIR" "$DEST_DIR"
backup "/boot"      "$PREV_BKUP_DIR" "$DEST_DIR"
backup "/etc"       "$PREV_BKUP_DIR" "$DEST_DIR"
backup_home "/home" "$PREV_BKUP_DIR" "$DEST_DIR"
backup "/root"      "$PREV_BKUP_DIR" "$DEST_DIR"
backup "/sbin"      "$PREV_BKUP_DIR" "$DEST_DIR"
backup "/lib"       "$PREV_BKUP_DIR" "$DEST_DIR"
backup "/lib64"     "$PREV_BKUP_DIR" "$DEST_DIR"
backup "/usr"       "$PREV_BKUP_DIR" "$DEST_DIR"
backup "/var"       "$PREV_BKUP_DIR" "$DEST_DIR"

#=======================
# ...to here.
#=======================

(LC_ALL=C ; df "${MOUNTPOINT}")

after_backup

(LC_ALL=C ; echo "[$(date "$DATE_FMT")]: Backup completed.") | tee -a "$LOG"
ret=0

exit ${ret}
