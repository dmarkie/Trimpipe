#!/bin/bash
#SBATCH --job-name FastQC
#SBATCH --time	24:00:00
#SBATCH --mem	1G
#SBATCH --cpus-per-task	2
#SBATCH --error slurm/fastqc_%A_%a-%j.out
#SBATCH --output slurm/fastqc_%A_%a-%j.out

function usage () {
echo -e "\

\nThis script is designed for FastQC analysis of fastq files.

usage: $0 options:

-h 	Print full help/usage information.

Optional:

-t	To specify when the input files should be the trimmed versions. 

"
}
source ${WORK_PATH}/parameters.sh
INPUT=${FILELIST[$(( $SLURM_ARRAY_TASK_ID - 1 ))]}
while getopts "th" OPTION; do 
	case $OPTION in 
		h)
			usage
			exit 0
			;;
		t)
			INPUT=${TRIMFILELIST[$(( $SLURM_ARRAY_TASK_ID - 1 ))]}
			;;
	esac
done
mkdir -p ${WORK_PATH}/FastQC
#Generate fastqc analysis 
module purge
module load FastQC
if [ ! -f ${WORK_PATH}/FastQC/$(basename ${INPUT} .fastq.gz).fastqc.done ]; then
	COMMAND="fastqc ${INPUT} -f fastq -o ${WORK_PATH}/FastQC/"
	echo ${COMMAND}
	eval ${COMMAND} || exit 1
	if [ -f ${WORK_PATH}/FastQC/$(basename ${INPUT} .fastq.gz)_fastqc.html ]; then
		touch ${WORK_PATH}/FastQC/$(basename ${INPUT} .fastq.gz).fastqc.done
	else
		echo -e "FAIL: FastQC output ${WORK_PATH}/FastQC/$(basename ${INPUT} .fastq.gz)_fastqc.html not produced"
		exit 1
	fi
else
	(echo "FastQC for $(basename ${INPUT}) already complete" 1>&2)
fi
