#!/bin/bash -e

echo ">>>>> ChIPseq analysis with Homer"
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> $(basename $0) $*"

function usage {
echo -e "usage: $(basename $0) -k NGSANE -f FASTQ -r REFERENCE -o OUTDIR [OPTIONS]"
exit
}

# Script for ChIP-seq peak calling using Homer.
# It takes read alignments in .bam format.
# It produces output files: peak regions in bed format
# author: Fabian Buske
# date: August 2013

# QCVARIABLES,Resource temporarily unavailable
if [ ! $# -gt 3 ]; then usage ; fi

#DEFAULTS
THREADS=8

#INPUTS                                                                                                           
while [ "$1" != "" ]; do
    case $1 in
        -k | --toolkit )        shift; CONFIG=$1 ;; # location of the NGSANE repository
        -t | --threads )        shift; THREADS=$1 ;; # number of CPUs to use
        -f | --bam )            shift; f=$1 ;; # bam file
        -o | --outdir )         shift; MYOUT=$1 ;; # output dir 
        -h | --help )           usage ;;
        * )                     echo "don't understand "$1
    esac
    shift
done

#PROGRAMS
. $CONFIG
. ${NGSANE_BASE}/conf/header.sh
. $CONFIG

echo "********** programs"
for MODULE in $MODULE_HOMERCHIPSEQ; do module load $MODULE; done  # save way to load modules that itself load other modules

export PATH=$PATH_HOMERCHIPSEQ:$PATH
module list
echo "PATH=$PATH"
#this is to get the full path (modules should work but for path we need the full path and this is the\
# best common denominator)
echo -e "--samtools--\n "$(samtools 2>&1 | head -n 3 | tail -n-2)
[ -z "$(which samtools)" ] && echo "[ERROR] no samtools detected" && exit 1
echo -e "--R       --\n "$(R --version | head -n 3)
[ -z "$(which R)" ] && echo "[ERROR] no R detected" && exit 1
echo -e "--homer   --\n "$(which makeTagDirectory)
[ -z "$(which makeTagDirectory)" ] && echo "[ERROR] homer not detected" && exit 1

# get basename of f
n=${f##*/}
c=${CHIPINPUT##*/}

if [ -n "$DMGET" ]; then
    echo "********** reacall files from tape"
    dmget -a $f
    dmls -l $f
fi

#homer likes to write in the current directory, so change to target
CURDIR=$(pwd)
cd $MYOUT

echo "********* make tag directory"
TAGDIRECTORY=$MYOUT/${n/%.$ASD.bam/_homer}
mkdir -p $TAGDIRECTORY
RUN_COMMAND="makeTagDirectory $TAGDIRECTORY $f $HOMER_CHIPSEQ_TAGDIR_ADDPARAM"
echo $RUN_COMMAND
eval $RUN_COMMAND


if [ -n "$CHIPINPUT" ];then
    TAGDIRECTORY=$MYOUT/${n/%.$ASD.bam/_homer}
    mkdir -p ${TAGDIRECTORY}_input
    cp $CHIPINPUT ${TAGDIRECTORY}
    RUN_COMMAND="makeTagDirectory ${TAGDIRECTORY}_input ${TAGDIRECTORY}/$c $HOMER_CHIPSEQ_TAGDIR_ADDPARAM"
    echo $RUN_COMMAND && eval $RUN_COMMAND
    rm $TAGDIRECTORY/$c
    INPUT=${c/.$ASD.bam/}
else
    INPUT="NONE"
fi

echo "********* find peaks"

RUN_COMMAND="findPeaks $TAGDIRECTORY -style $HOMER_CHIPSEQ_STYLE  $HOMER_CHIPSEQ_FINDPEAKS_ADDPARAM -o auto"
if [ -n "$CHIPINPUT" ];then
  RUN_COMMAND="$RUN_COMMAND -i ${TAGDIRECTORY}_input"  
fi
echo $RUN_COMMAND && eval $RUN_COMMAND

if [ "$HOMER_CHIPSEQ_STYLE" == "factor" ]; then
    pos2bed.pl $MYOUT/${n/.$ASD.bam/_homer}/peaks.txt > $MYOUT/${n/.$ASD.bam/}-${INPUT}_peaks.bed
    grep "^#" $MYOUT/${n/.$ASD.bam/_homer}/peaks.txt > $MYOUT/${n/.$ASD.bam/}-${INPUT}.summary.txt

elif [ "$HOMER_CHIPSEQ_STYLE" == "histone" ]; then
    pos2bed.pl $MYOUT/${n/.$ASD.bam/_homer}/regions.txt > $MYOUT/${n/.$ASD.bam/}-${INPUT}_regions.bed
    grep "^#" $MYOUT/${n/.$ASD.bam/_homer}/regions.txt > $MYOUT/${n/.$ASD.bam/}-${INPUT}.summary.txt
fi

# cleanup
if [ -z "$HOMER_KEEPTAGDIRECTORY" ]; then
   rm $TAGDIRECTORY/*.tags.tsv
fi

if [ -n "$CHIPINPUT" ]; then
    rm -rf ${TAGDIRECTORY}_input
fi

# and back to where we used to be
cd $CURDIR

echo ">>>>> ChIPseq analysis with Homer - FINISHED"
echo ">>>>> enddate "`date`
