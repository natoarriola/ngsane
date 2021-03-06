#!/bin/bash

# Call variants with samtools
# author: Denis C. Bauer
# date: Feb.2013

# messages to look out for -- relevant for the QC.sh script:
# 

echo ">>>>> Collect Variants after calling with sam "
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> job_name "$JOB_NAME
echo ">>>>> job_id "$JOB_ID
echo ">>>>> $(basename $0) $*"


function usage {
echo -e "usage: $(basename $0) -k CONFIG -f BAM -o OUTDIR [OPTIONS]

Variant calling with sam

required:
  -k | --toolkit <path>     config file
  -f <files>                bam files
  -o <dir>
"
exit
}


if [ ! $# -gt 3 ]; then usage ; fi

#DEFAULTS

#INPUTS
while [ "$1" != "" ]; do
    case $1 in
        -k | --toolkit )        shift; CONFIG=$1 ;; # location of the NGSANE repository
        -f             )        shift; FILES=${1//,/ } ;; # bam files
        -o             )        shift; OUTDIR=$1 ;; # outputdir
        --recover-from )        shift; RECOVERFROM=$1 ;; # attempt to recover from log file
        -h | --help    )        usage ;;
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
for MODULE in $MODULE_SAMVAR; do module load $MODULE; done  # save way to load modules that itself load other modules
export PATH=$PATH_SAMVAR:$PATH
module list
echo "PATH=$PATH"
#this is to get the full path (modules should work but for path we need the full path and this is the\
# best common denominator)
PATH_GATK=$(dirname $(which GenomeAnalysisTK.jar))
PATH_IGVTOOLS=$(dirname $(which igvtools.jar))

echo "[NOTE] set java parameters"
JAVAPARAMS="-Xmx"$(python -c "print int($MEMORY_SAMVAR*0.8)")"g -Djava.io.tmpdir="$TMP"  -XX:ConcGCThreads=1 -XX:ParallelGCThreads=1" 
unset _JAVA_OPTIONS
echo "JAVAPARAMS "$JAVAPARAMS

echo -e "--NGSANE      --\n" $(trigger.sh -v 2>&1)
echo -e "--JAVA        --\n" $(java -Xmx200m -version 2>&1)
[ -z "$(which java)" ] && echo "[ERROR] no java detected" && exit 1
echo -e "--igvtools    --\n "$(java $JAVAPARAMS -jar $PATH_IGVTOOLS/igvtools.jar version 2>&1)
[ ! -f $PATH_IGVTOOLS/igvtools.jar ] && echo "[ERROR] no igvtools detected" && exit 1
echo -e "--GATK        --\n "$(java $JAVAPARAMS -jar $PATH_GATK/GenomeAnalysisTK.jar --version 2>&1)
[ ! -f $PATH_GATK/GenomeAnalysisTK.jar ] && echo "[ERROR] no GATK detected" && exit 1


echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="parameters"

# get basename of f
n=${f##*/}

# delete old bam file
#if [ -z "$RECOVERFROM" ]; then
#    if [ -e $OUTDIR/${n/%$READONE.$FASTQ/.$ASD.bam} ]; then rm $OUTDIR/${n/%$READONE.$FASTQ/.$ASD.bam}; fi
#    if [ -e $OUTDIR/${n/%$READONE.$FASTQ/.$ASD.bam}.stats ]; then rm $OUTDIR/${n/%$READONE.$FASTQ/.$ASD.bam}.stats; fi
#    if [ -e $OUTDIR/${n/%$READONE.$FASTQ/.$ASD.bam}.dupl ]; then rm $OUTDIR/${n/%$READONE.$FASTQ/.$ASD.bam}.dupl; fi
#fi
# ensure dir is there
if [ ! -d $OUTDIR ]; then mkdir -p $OUTDIR; fi

# prep for joining
VARIANTS=""
NAMES=""
for f in $FILES; do
    i=${f/$TASK_BWA/$TASK_BWA"-"$TASK_SAMVAR} #point to var folder
    i=${i/bam/"clean.vcf"} # correct ending
    b=$(basename $i)
    arrIN=(${b//./ })
    name=${arrIN[0]}
    NAMES=$NAMES"$name,"
    VARIANTS=$VARIANTS" --variant:$name $i "
done

echo $VARIANTS

REGION=""
if [ -n "$REF" ]; then echo $REF; REGION="-L $REF"; fi

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="recall files from tape"

if [ -n "$DMGET" ]; then
	dmget -a $FILES
	dmget -a $OUTDIR/*
fi
    
echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="join with GATK"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    java $JAVAPARAMS -jar $PATH_GATK/GenomeAnalysisTK.jar -l INFO \
       -R $FASTA \
       -T CombineVariants \
       $VARIANTS \
       -o $OUTDIR/joined.vcf \
       -genotypeMergeOptions PRIORITIZE \
       $REGION \
       -priority $NAMES

    # mark checkpoint
    if [ -f $OUTDIR/joined.vcf ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi

fi 

################################################################################
CHECKPOINT="index for IGV"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    java $JAVAPARAMS -jar $PATH_IGVTOOLS/igvtools.jar index $OUTDIR/joined.vcf

    # mark checkpoint
    echo -e "\n********* $CHECKPOINT\n" && unset RECOVERFROM
fi

################################################################################
echo ">>>>> Join variant after calling with sam - FINISHED"
echo ">>>>> enddate "`date`

