#!/bin/bash

# Script to run TopHat program
# It takes comma-seprated list of files containing short sequence reads in fasta or fastq format and bowtie index files as input.
# It produces output files: read alignments in .bam format and other files.
# author: Chikako Ragan, Denis Bauer
# date: Jan. 2011



# messages to look out for -- relevant for the QC.sh script:
# QCVARIABLES,truncated file


echo ">>>>> readmapping with Tophat "
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> job_name "$JOB_NAME
echo ">>>>> job_id "$JOB_ID
echo ">>>>> tophatcuff.sh $*"


function usage {
echo -e "usage: $(basename $0) -k NGSANE -f FASTA -r REFERENCE -o OUTDIR [OPTIONS]

Script running read mapping for single and paired DNA reads from fastq files
It expects a fastq file, pairdend, reference genome  as input and 
It runs BWA, converts the output to .bam files, adds header information and
writes the coverage information for IGV.

required:
  -k | --toolkit <path>     location of the NGSANE repository 
  -f | --fastq <file>       fastq file
  -r | --reference <file>   reference genome
  -o | --outdir <path>      output dir

options:
  -t | --threads <nr>       number of CPUs to use (default: 1)
  -i | --rgid <name>        read group identifier RD ID (default: exp)
  -l | --rglb <name>        read group library RD LB (default: qbi)
  -p | --rgpl <name>        read group platform RD PL (default: illumna)
  -s | --rgsi <name>        read group sample RG SM prefac (default: )
  -R | --region <ps>        region of specific interest, e.g. targeted reseq
                             format chr:pos-pos
  -S | --sam                do not convert to bam file (default confert); not the
                             resulting sam file is not duplicate removed
  --forceSingle             run single end eventhough second read is present
"
exit
}

if [ ! $# -gt 3 ]; then usage ; fi

#DEFAULTS
THREADS=1
EXPID="exp"           # read group identifier RD ID
LIBRARY="qbi"         # read group library RD LB
PLATFORM="illumina"   # read group platform RD PL
DOBAM=1               # do the bam file
FORCESINGLE=0
INSERT=200
MEMORY=2G

#INPUTS
while [ "$1" != "" ]; do
	case $1 in
	-k | toolkit )          shift; CONFIG=$1 ;; # ENSURE NO VARIABLE NAMES FROM CONFIG
	-t | --threads )        shift; THREADS=$1 ;; # number of CPUs to use
	-f | --fastq )          shift; f=$1 ;; # fastq file
	-r | --reference )      shift; FASTA=$1 ;; # reference genome
	-o | --outdir )         shift; OUTDIR=$1 ;; # output dir
	-a | --annot )          shift; REFSEQGTF=$1 ;; # refseq annotation
	-i | --insert )         shift; INSERT=$1 ;; #mate insert size
	
	-l | --rglb )           shift; LIBRARY=$1 ;; # read group library RD LB
	-p | --rgpl )           shift; PLATFORM=$1 ;; # read group platform RD PL
	-s | --rgsi )           shift; SAMPLEID=$1 ;; # read group sample RG SM (pre)
	-R | --region )         shift; SEQREG=$1 ;; # (optional) region of specific interest, e.g. targeted reseq
	-S | --sam )            DOBAM=0 ;;
	
	--forceSingle )         FORCESINGLE=1;;
	-h | --help )           usage ;;
	* )                     echo "dont understand $1"
	esac
	shift
done


#PROGRAMS (note, both configs are necessary to overwrite the default, here:e.g.  TASKTOPHAT)
. $CONFIG
. ${NGSANE_BASE}/conf/header.sh
. $CONFIG

JAVAPARAMS="-Xmx"$(expr $MEMORY_TOPHAT - 1 )"G -Djava.io.tmpdir="$TMP
echo "JAVAPARAMS "$JAVAPARAMS

echo "********** programs"
for MODULE in $MODULE_TOPHATCUFF; do module load $MODULE; done  # save way to load modules that itself load other modules
export PATH=$PATH_TOPHATCUFF:$PATH
module list
echo $PATH
#this is to get the full path (modules should work but for path we need the full path and this is the\
# best common denominator)
PATH_IGVTOOLS=$(dirname $(which igvtools.jar))
PATH_PICARD=$(dirname $(which MarkDuplicates.jar))
echo -e "--JAVA     --\n" $(java $JAVAPARAMS -version 2>&1)a
[ -z "$(which java)" ] && echo "[ERROR] no java detected" && exit 1
echo -e "--bowtie2  --\n "$(bowtie2 --version)
[ -z "$(which bowtie2)" ] && echo "[ERROR] no bowtie2 detected" && exit 1
echo -e "--samtools --\n "$(samtools 2>&1 | head -n 3 | tail -n-2)
[ -z "$(which samtools)" ] && echo "[ERROR] no samtools detected" && exit 1
echo -e "--R        --\n "$(R --version | head -n 3)
[ -z "$(which R)" ] && echo "[ERROR] no R detected" && exit 1
echo -e "--igvtools --\n "$(java -jar $JAVAPARAMS $PATH_IGVTOOLS/igvtools.jar version 2>&1)
[ ! -f $PATH_IGVTOOLS/igvtools.jar ] && echo "[ERROR] no igvtools detected" && exit 1
echo -e "--picard   --\n "$(java -jar $JAVAPARAMS $PATH_PICARD/MarkDuplicates.jar --version 2>&1)
[ ! -f $PATH_PICARD/MarkDuplicates.jar ] && echo "[ERROR] no picard detected" && exit 1
echo -e "--samstat  --\n "$(samstat | head -n 2 | tail -n1)
[ -z "$(which samstat)" ] && echo "[ERROR] no samstat detected" && exit 1
echo -e "--bedtools --\n "$(bedtools --version)
[ -z "$(which bedtools)" ] && echo "[ERROR] no bedtools detected" && exit 1
echo -e "--htSeq    --\n "$(htseq-count | tail -n 1)
[ -z "$(which htseq-count)" ] && [ -n "$GENCODEGTF" ] && echo "[ERROR] no htseq-count detected" && exit 1

#SAMPLENAME
# get basename of f
n=${f##*/}

# get info about input file
FASTASUFFIX=${FASTA##*.}
BAMFILE=$OUTDIR/../${n/_$READONE.$FASTQ/.tph.bam}

CUFOUT=${OUTDIR/$TASKTOPHAT/$TASKCUFF}

#remove old files
if [ -d $OUTDIR ]; then rm -r $OUTDIR; fi
if [ -d $CUFOUT ]; then rm -r $CUFOUT; fi

if [ -n "$DMGET" ]; then
	echo "********** reacall files from tape"
	dmget -a $(dirname $FASTA)/*
	dmget -a ${f/$READONE/"*"}
fi

#is paired ?                                                                                                      
if [ -e ${f/$READONE/$READTWO} ] && [ "$FORCESINGLE" = 0 ]; then
    PAIRED="1"
    f2=${f/$READONE/$READTWO}
else
    PAIRED="0"
fi

#is ziped ?
ZCAT="cat" # always cat
if [[ $f = *.gz ]]; then
    ZCAT="zcat";
#    echo "unzip first"
#    f=${f/fastq.gz/fastq}
#    if [ ! -e $f ]; then gunzip -c $f.gz >$f; fi
#    if [ -n "$f2" ]; then
#	f2=${f2/fastq.gz/fastq}
#	if [ ! -e $f2 ]; then gunzip -c $f2.gz >$f2; fi
#    fi
#    n=${n/fastq.gz/fastq}
fi

## generating the index files
if [ ! -e ${FASTA/.${FASTASUFFIX}/}.1.bt2 ]; then echo ">>>>> make .bt2"; bowtie2-build $FASTA ${FASTA/.${FASTASUFFIX}/}; fi                                                                                      
if [ ! -e $FASTA.fai ]; then echo ">>>>> make .fai"; samtools faidx $FASTA; fi

mkdir $OUTDIR
echo "********* tophat"
if [ -z "$RNA_SEQ_LIBRARY_TYPE" ]; then 
	echo "[ERROR] RNAseq library type not set (RNA_SEQ_LIBRARY_TYPE): either fr-unstranded or fr-firststrand"
	exit 1; 
else
	echo "RNAseq library type: $RNA_SEQ_LIBRARY_TYPE"
fi

tophat -p $THREADS --library-type "$RNA_SEQ_LIBRARY_TYPE" -o $OUTDIR ${FASTA/.${FASTASUFFIX}/} $f $f2

echo "********* merge mapped and unmapped"
#ln -f  $OUTDIR/accepted_hits.bam $BAMFILE
samtools merge -f $BAMFILE.tmp.bam $OUTDIR/accepted_hits.bam $OUTDIR/unmapped.bam
samtools sort $BAMFILE.tmp.bam ${BAMFILE/.bam/.samtools}

echo "********* reorder tophat output to match reference"
if [ ! -e ${FASTA/.${FASTASUFFIX}/}.dict ]; then 
	java $JAVAPARAMS -jar $PATH_PICARD/CreateSequenceDictionary.jar \
		REFERENCE=$FASTA \
		OUTPUT=${FASTA/.$FASTASUFFIX/}.dict
fi

## sort bam header according to fasta (chromosome order) due to tophat's 
## own ordering, which can pose problems for other programs 
java -jar $JAVAPARAMS $PATH_PICARD/ReorderSam.jar \
     INPUT=${BAMFILE/.bam/.samtools}.bam \
     OUTPUT=$BAMFILE \
     REFERENCE=$FASTA \
     ALLOW_INCOMPLETE_DICT_CONCORDANCE=TRUE \
     ALLOW_CONTIG_LENGTH_DISCORDANCE=TRUE \
     VALIDATION_STRINGENCY=LENIENT

rm $BAMFILE.tmp.bam ${BAMFILE/.bam/.samtools}.bam

##statistics
echo "********* flagstat"
samtools flagstat $BAMFILE >$BAMFILE.stats
READ1=`$ZCAT $f | wc -l | gawk '{print int($1/4)}' `
FASTQREADS=$READ1
if [ -n "$f2" ]; then 
	READ2=`$ZCAT $f2 | wc -l | gawk '{print int($1/4)}' `;
	let FASTQREADS=$READ1+$READ2
fi
echo $FASTQREADS" fastq reads" >>$BAMFILE.stats
JUNCTION=`wc -l $OUTDIR/junctions.bed | cut -d' ' -f 1 `
echo $JUNCTION" junction reads" >> $BAMFILE.stats
## get junction genes overlapping exons +-200bp
JUNCTGENE=`$BEDTOOLS/windowBed -a $OUTDIR/junctions.bed -b $REFSEQGTF -u -w 200 | wc -l | cut -d' ' -f 1 `
echo $JUNCTGENE" junction reads NCBIM37" >> $BAMFILE.stats

##index
echo "********* index"
samtools index $BAMFILE

echo "********* calculate inner distance"
if [ ! -e $OUTDIR/../metrices ]; then mkdir $OUTDIR/../metrices ; fi
THISTMP=$TMP/$n$RANDOM #mk tmp dir because picard writes none-unique files
mkdir $THISTMP
java $JAVAPARAMS -jar $PATH_PICARD/CollectMultipleMetrics.jar \
    INPUT=$BAMFILE \
    REFERENCE_SEQUENCE=$FASTA \
    OUTPUT=$OUTDIR/../metrices/$(basename $BAMFILE) \
    VALIDATION_STRINGENCY=LENIENT \
    PROGRAM=CollectAlignmentSummaryMetrics \
    PROGRAM=CollectInsertSizeMetrics \
    PROGRAM=QualityScoreDistribution \
    TMP_DIR=$THISTMP
for im in $( ls $OUTDIR/../metrices/$(basename $BAMFILE)*.pdf ); do
    convert $im ${im/pdf/jpg}
done
rm -r $THISTMP

##coverage for IGV
echo "********* coverage track"
java $JAVAPARAMS -jar $PATH_IGVTOOLS/igvtools.jar count $BAMFILE \
    $BAMFILE.cov.tdf ${FASTA/$FASTASUFFIX/}genome

echo "********* samstat"
samstat $BAMFILE


##run cufflinks
echo "********* cufflinks"
echo ">>>>> from $BAMFILE to $CUFOUT"

#specify REFSEQ or Gencode GTF depending on analysis desired.

## add GTF file if present
if [ -n "$GENCODEGTF" ]; then 
	GENCODEGTF="$GENCODEGTF"; 
	cufflinks --quiet --GTF-guide $GENCODEGTF -p $THREADS --library-type $RNA_SEQ_LIBRARY_TYPE -o $CUFOUT $BAMFILE 

elif [ -n "$REFSEQGTF" ]; then 
	REFSEQGTF="$REFSEQGTF"; 
	cufflinks --quiet --GTF-guide $REFSEQGTF -p $THREADS --library-type $RNA_SEQ_LIBRARY_TYPE -o $CUFOUT $BAMFILE 

else
	# non reference guided
    echo "non reference guided run (neither GENCODEGTF nor REFSEQGTF defined)"
    cufflinks --quiet -r $FASTA -p $THREADS --library-type $RNA_SEQ_LIBRARY_TYPE \
         -o $CUFOUT $BAMFILE    
fi

echo ">>>>> alignment with TopHat - FINISHED"

# add Gencode GTF if present 
if [ -n "$GENCODEGTF" ]; then 
	echo "********* htseq-count"

	GENCODEGTF="$GENCODEGTF"; 
	if [ $RNA_SEQ_LIBRARY_TYPE = "fr-unstranded" ]; then
	       echo "********* library is fr-unstranded run ht seq count stranded=no" 
	       HT_SEQ_OPTIONS="--stranded=no"
	elif [ $RNA_SEQ_LIBRARY_TYPE = "fr-firststrand" ]; then
	       echo "********* library is fr-firststrand run ht seq count stranded=yes"
	       HT_SEQ_OPTIONS="--stranded=yes"
	fi
	

	##add secondstrand
	annoF=${GENCODEGTF##*/}
#	echo ${annoF}
	anno_version=${annoF%.*}
	
	HTOUTDIR=$OUTDIR/../htseq_count
#	echo ${HTOUTDIR}
	mkdir -p $HTOUTDIR
	
	samtools sort -n $OUTDIR/accepted_hits.bam $OUTDIR/accepted_hits_sorted.bam
	
	samtools view $OUTDIR/accepted_hits_sorted.bam  | htseq-count --type="gene" $HT_SEQ_OPTIONS - $GENCODEGTF > $HTOUTDIR/${anno_version}.gene
	
	samtools view $OUTDIR/accepted_hits_sorted.bam  | htseq-count --type="transcript" --idattr="transcript_id" $HT_SEQ_OPTIONS - $GENCODEGTF > $HTOUTDIR/${anno_version}.transcript

    rm $OUTDIR/accepted_hits_sorted.bam
    
	echo ">>>>> Read counting with htseq count - FINISHED"

##make bigwigs for UCSC using gencode masked reads

    if [ $RNA_SEQ_LIBRARY_TYPE = "fr-unstranded" ]; then
	    echo "********* make bigwigs library is fr-unstranded "
	    BAM2BW_OPTION_1="FALSE"
	    BAM2BW_OPTION_2="FALSE"
    elif [ $RNA_SEQ_LIBRARY_TYPE = "fr-firststrand" ]; then
	    echo "********* make bigwigs library is fr-firststrand "
	    BAM2BW_OPTION_1="TRUE"
	    BAM2BW_OPTION_2="TRUE"
    fi

	BIGWIGSDIR=$OUTDIR/../bigwigs
	#	echo ${BIGWIGSDIR}
	mkdir -p $BIGWIGSDIR
	
	#file_arg sample_arg stranded_arg firststrand_arg paired_arg
	Rscript --vanilla ${NGSANE_BASE}/tools/BamToBw.R $OUTDIR/accepted_hits.bam ${n} $BAM2BW_OPTION_1 $BAM2BW_OPTION_2 $BIGWIGSDIR
	
	echo ">>>>> make bigwigs - FINISHED"
	
	echo "********* calculate RPKMs per Gencode Gene "
	
	Rscript --vanilla ${NGSANE_BASE}/tools/CalcGencodeGeneRPKM.R $GENCODEGTF $HTOUTDIR/${anno_version}.gene ${n}gene ${anno_version}
	
	echo "********* calculate RPKMs per Gencode Transcript "
	
	Rscript --vanilla ${NGSANE_BASE}/tools/CalcGencodeRPKM.R $GENCODEGTF $HTOUTDIR/${anno_version}.transcript ${n}transcript ${anno_version}
	
	echo ">>>>> Gencode RPKM calculation - FINISHED"

	echo "********* Create filtered bamfile "      
	
	grep -P "gene_type \"rRNA\"" $GENCODEGTF > $OUTDIR/mask.gff
	grep -P "gene_type \"Mt_tRNA\"" $GENCODEGTF >> $OUTDIR/mask.gff
	grep -P "gene_type \"Mt_rRNA\"" $GENCODEGTF >> $OUTDIR/mask.gff
	grep -P "gene_type \"tRNA\"" $GENCODEGTF >> $OUTDIR/mask.gff
	
	grep -P "gene_type \"rRNA_pseudogene\"" $GENCODEGTF >> $OUTDIR/mask.gff
	grep -P "gene_type \"tRNA_pseudogene\"" $GENCODEGTF >> $OUTDIR/mask.gff
	grep -P "gene_type \"Mt_tRNA_pseudogene\"" $GENCODEGTF >> $OUTDIR/mask.gff
	grep -P "gene_type \"Mt_rRNA_pseudogene\"" $GENCODEGTF >> $OUTDIR/mask.gff
	
	        
	intersectBed -v -abam $OUTDIR/accepted_hits.bam -b $OUTDIR/mask.gff > $OUTDIR/tophat_aligned_reads_masked.bam    
	    
	samtools index $OUTDIR/tophat_aligned_reads_masked.bam
	    
	echo ">>>>> Create filtered bamfile - FINISHED"
fi


echo ">>>>> enddate "`date`