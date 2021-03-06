#!/bin/bash

###############################################################################
# predefine parameter
run="run.conf"
NCPU=1
###############################################################################


###############################################################################
# search argument list
for arg in "$@"; do
    par=${arg%%=*}
    val=${arg##*=}
    if [ "$par" == "run" ]; then
        run=$val
    elif [ "$par" == "ncpu" ]; then
        NCPU=$val
    elif [ "$arg" == "-debug" ]; then
        FLAG_DEBUG=1
    else
        echo "error: unkown parameter " $arg
        exit -1
    fi
done
###############################################################################


###############################################################################
# check for run configuration
if [ ! -f "$run" ]; then
	echo error: missing file "$run"; echo
	exit -1
fi
cp $run run_input
###############################################################################


###############################################################################
# run FLARE

# Absolute path to this script
SCRIPT=$(readlink -f "$0")

# Absolute path this script is in
FLARE_PATH=$(dirname "$SCRIPT")


if [ "$FLAG_DEBUG" == "" ]; then
	if [ "$NCPU" == 1 ]; then
		$FLARE_PATH/flare_bin
	else
		mpiexec -n $NCPU $FLARE_PATH/flare_bin
	fi
else # for debugging only
	if [ "$NCPU" == 1 ]; then
		gdb $FLARE_PATH/flare_bin_debug
	else
		mpiexec -n $NCPU xterm -e gdb $FLARE_PATH/flare_bin_debug
	fi
fi
###############################################################################


###############################################################################
# cleanup
rm -rf input
rm -rf run_input
###############################################################################
