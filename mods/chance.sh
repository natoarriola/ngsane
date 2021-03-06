#!/bin/bash -e

# Script for ChIP-seq QC using Chance.
# It takes read alignments in .bam format.
# It produces output files: peak regions in bed format
# author: Fabian Buske
# date: August 2013

echo ">>>>> ChIPseq QC with Chance"
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> job_name "$JOB_NAME
echo ">>>>> job_id "$JOB_ID
echo ">>>>> $(basename $0) $*"

function usage {
echo -e "usage: $(basename $0) -k NGSANE -f FASTQ -o OUTDIR [OPTIONS]"
exit
}

# QCVARIABLES,Resource temporarily unavailable
# RESULTFILENAME <DIR>/<TASK>/<SAMPLE>.pdf

if [ ! $# -gt 3 ]; then usage ; fi

#INPUTS                                                                                                           
while [ "$1" != "" ]; do
    case $1 in
        -k | --toolkit )        shift; CONFIG=$1 ;; # location of the NGSANE repository
        -f | --bam )            shift; f=$1 ;; # bam file
        -o | --outdir )         shift; OUTDIR=$1 ;; # output dir 
        --recover-from )        shift; RECOVERFROM=$1 ;; # attempt to recover from log file
        -h | --help )           usage ;;
        * )                     echo "don't understand "$1
    esac
    shift
done

#PROGRAMS
. $CONFIG
. ${NGSANE_BASE}/conf/header.sh
. $CONFIG

################################################################################
CHECKPOINT="programs"

for MODULE in $MODULE_CHANCE; do module load $MODULE; done  # save way to load modules that itself load other modules

export PATH=$PATH_CHANCE:$PATH
module list
echo "PATH=$PATH"
#this is to get the full path (modules should work but for path we need the full path and this is the\
# best common denominator)

echo -e "--NGSANE      --\n" $(trigger.sh -v 2>&1)
echo -e "--chance      --\n "$(which run_chance_com.sh 2>&1)
[ -z "$(which run_chance_com.sh)" ] && echo "[ERROR] run_chance_com.sh not detected" && exit 1
echo -e "--Matlab (MCR)--\n "$(echo "$MCRROOT")
[ -z "$(echo $MCRROOT)" ] && echo "[ERROR] no matlab runtime environment detected" && exit 1
echo -e "--R           --\n "$(R --version | head -n 3)
[ -z "$(which R)" ] && echo "[ERROR] no R detected" && exit 1

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="parameters"

# get basename of f
n=${f##*/}
c=${CHIPINPUT##*/}

if [ -z "$CHIPINPUT" ] || [ ! -f $CHIPINPUT ]; then
    echo "[ERROR] input control not provided or invalid (CHIPINPUT)"
    exit 1
fi

if [ -z "$GENOME_ASSEMBLY" ]; then 
    echo "[ERROR] GENOME_ASSEMBLY not specified."
    exit 1
fi 

if [ -z "$EXPERIMENTID" ] &&  [ -z "$EXPERIMENTPATTERN" ]; then
    echo "[WARN] no experiment id or pattern given"
fi

CHANCE="`which run_chance_com.sh` `echo $MCRROOT`"
echo "[NOTE] Chance Environment: $CHANCE"

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="recall files from tape"

if [ -n "$DMGET" ]; then
	dmget -a ${f}
	dmget -a ${OUTDIR}
	[ -n $CHIPINPUT ] && dmget -a $CHIPINPUT
fi

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="compute IPstrength"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else

    RUN_COMMAND="${CHANCE} IPStrength -b ${GENOME_ASSEMBLY} -t bam -o ${OUTDIR}/${n/.$ASD.bam/}-${c/.$ASD.bam/}.IPstrength --ipfile $f --ipsample ${n/.$ASD.bam/} --inputfile ${CHIPINPUT} --inputsample ${c/.$ASD.bam/}"
    echo $RUN_COMMAND && eval $RUN_COMMAND
    
    # mark checkpoint
    if [ -f ${OUTDIR}/${n/.$ASD.bam/}-${c/.$ASD.bam/}.IPstrength ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi

fi

################################################################################
CHECKPOINT="compare with ENCODE"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else

    if [ -n "$EXPERIMENTID" ] || [ -n "$EXPERIMENTPATTERN" ]; then

        if [ -z "$EXPERIMENTID" ]; then
            EXPERIMENTID=$(echo "$n" | sed -rn $EXPERIMENTPATTERN)
        fi
        
        RUN_COMMAND="${CHANCE} compENCODE -b ${GENOME_ASSEMBLY} -t bam -o ${OUTDIR}/${n}-${c}.compENCODE -e $EXPERIMENTID --ipfile ${f} --ipsample ${n/.$ASD.bam/} --inputfile ${CHIPINPUT} --inputsample ${c/.$ASD.bam/}"
        echo $RUN_COMMAND && eval $RUN_COMMAND
        
        # mark checkpoint
        if [ -f ${OUTDIR}/${n/.$ASD.bam/}-${c/.$ASD.bam/}.compENCODE ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi

    else
        echo "[NOTE] skip ENCODE comparison "
        echo -e "\n********* $CHECKPOINT\n"
    fi
fi

################################################################################
CHECKPOINT="make plots"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else
    
    Rscript --vanilla ${NGSANE_BASE}/tools/makeChancePlots.R $f $CHIPINPUT ${n/.$ASD.bam/} ${c/.$ASD.bam/} $OUTDIR

    # mark checkpoint
    if [ -f $OUTDIR/${n/.$ASD.bam/.pdf} ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi

fi
################################################################################
[ -e $OUTDIR/${n/.$ASD.bam/.pdf}.dummy ] && rm $OUTDIR/${n/.$ASD.bam/.pdf}.dummy
echo ">>>>> ChIPseq QC with Chance - FINISHED"
echo ">>>>> enddate "`date`