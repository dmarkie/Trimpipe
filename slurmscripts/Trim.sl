#!/bin/bash
#SBATCH --job-name Trim
#SBATCH --time	24:00:00
#SBATCH --mem	12G
#SBATCH --cpus-per-task	4
#SBATCH --error slurm/trim_%j.out
#SBATCH --output slurm/trim_%j.out

function usage () {
echo -e "\

\nThis script is designed for FastQC analysis of fastq files.

usage: $0 options:

-h 	Print full help/usage information.

"
}

while getopts "h" OPTION; do 
	case $OPTION in 
		h)
			usage
			exit 0
			;;
	esac
done
source ${WORK_PATH}/parameters.sh

# need to complain and exit if no fastq files or output specified
if [ ! -e ${FILELIST[0]} ]; then
	echo "FAIL Read 1 ${FILELIST[0]} file does not exist!"
	exit 1
fi
if [ ! -e ${FILELIST[1]} ]; then
	echo "FAIL Read 2 ${FILELIST[1]} file does not exist!"
	exit 1
fi
if [ -z ${SAMPLE} ]; then
	(echo "FAIL: No sample was specified!" 1>&2)
	exit 1
fi

if [ ! -f ${WORK_PATH}/trim.done ]; then
	module purge
	module load Trimmomatic
	COMMAND="java -jar $EBROOTTRIMMOMATIC/trimmomatic-0.38.jar PE ${FILELIST[@]} ${WORK_PATH}/$(basename ${FILELIST[0]} .fastq.gz)_trimmed_paired.fastq.gz ${WORK_PATH}/$(basename ${FILELIST[0]} .fastq.gz)_trimmed_unpaired.fastq.gz ${WORK_PATH}/$(basename ${FILELIST[1]} .fastq.gz)_trimmed_paired.fastq.gz ${WORK_PATH}/$(basename ${FILELIST[1]} .fastq.gz)_trimmed_unpaired.fastq.gz ${TRIMPARAMETERS} -threads $SLURM_JOB_CPUS_PER_NODE"
	echo ${COMMAND}
	eval ${COMMAND} || exit 1
	touch ${WORK_PATH}/trim.done
else
	(echo "Trim for ${SAMPLE} already complete" 1>&2)
fi
