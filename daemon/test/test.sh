#! /bin/sh -e

# We steal the test-cli scripts.
cd test-cli

. scripts/vars.sh

scripts/setup.sh

DIR1=/tmp/lightning.$$.1
DIR2=/tmp/lightning.$$.2

REDIR1="$DIR1/output"
REDIR2="$DIR2/output"

if [ x"$1" = x"--valgrind" ]; then
    PREFIX1="valgrind --vgdb-error=1"
    PREFIX2="valgrind --vgdb-error=1"
    REDIR1="/dev/tty"
    REDIR2="/dev/tty"
elif [ x"$1" = x"--gdb1" ]; then
    PREFIX1="gdb --args -ex run"
    REDIR1="/dev/tty"
elif [ x"$1" = x"--gdb2" ]; then
    PREFIX2="gdb --args -ex run"
    REDIR2="/dev/tty"
fi

LCLI1="../daemon/lightning-cli --lightning-dir=$DIR1"
LCLI2="../daemon/lightning-cli --lightning-dir=$DIR2"

trap "echo Results in $DIR1 and $DIR2" EXIT
mkdir $DIR1 $DIR2
$PREFIX1 ../daemon/lightningd --log-level=debug --bitcoind-poll=1 --lightning-dir=$DIR1 > $REDIR1 &
$PREFIX2 ../daemon/lightningd --log-level=debug --bitcoind-poll=1 --lightning-dir=$DIR2 > $REDIR2 &

i=0
while ! $LCLI1 getlog | grep Hello; do
    sleep 1
    i=$(($i + 1))
    if [ $i -gt 10 ]; then
	echo Failed to start daemon 1 >&2
	exit 1
    fi
done

while ! $LCLI2 getlog | grep 'listener on port'; do
    sleep 1
    i=$(($i + 1))
    if [ $i -gt 10 ]; then
	echo Failed to start daemon 2 >&2
	exit 1
    fi
done

PORT2=`$LCLI2 getlog | sed -n 's/.*on port \([0-9]*\).*/\1/p'`

$LCLI1 connect localhost $PORT2 999999
sleep 2

# Expect them to be waiting for anchor.
$LCLI1 getpeers | grep STATE_OPEN_WAITING_OURANCHOR
$LCLI2 getpeers | grep STATE_OPEN_WAITING_THEIRANCHOR

# Now make it pass anchor.
$CLI generate 3

# They poll every second, so give them time to process.
sleep 2

$LCLI1 getpeers | grep STATE_NORMAL_HIGHPRIO
$LCLI2 getpeers | grep STATE_NORMAL_LOWPRIO

$LCLI1 stop
$LCLI2 stop
scripts/shutdown.sh

trap "rm -rf $DIR1 $DIR2" EXIT
