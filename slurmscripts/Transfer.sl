#!/bin/bash
#SBATCH --job-name Transfer
#SBATCH --time	1:00:00
#SBATCH --mem	1G
#SBATCH --error slurm/transfer_%j.out
#SBATCH --output slurm/transfer_%j.out

function usage () {
echo -e "\

\nThis script is designed to transfer a sample folder containing trimmed fastq files, with FastQC anaylsis, from the working directory to a final directory.

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
if [ -z ${PROJECT} ]; then
	(echo "FAIL: No output directory was specified!" 1>&2)
	exit 1
fi
if [ ! -f ${WORK_PATH}/trim.done ]; then 
	(echo "Can't find ${WORK_PATH}/trim.done, suggesting the trim has not completed." 1>&2)
	exit 1
fi

for FILE in ${FILELIST[@]}; do
	if [ ! -f ${WORK_PATH}/FastQC/$(basename ${FILE} .fastq.gz).fastqc.done ]; then 
		(echo "Can't find ${WORK_PATH}/FastQC/$(basename ${FILE} .fastq.gz).fastqc.done, suggesting this FastQC analysis has not completed." 1>&2)
		exit 1
	fi
done	
for FILE in ${TRIMFILELIST[@]}; do
	if [ ! -f ${WORK_PATH}/FastQC/$(basename ${FILE} .fastq.gz).fastqc.done ]; then 
		(echo "Can't find ${WORK_PATH}/FastQC/$(basename ${FILE} .fastq.gz).fastqc.done, suggesting this FastQC analysis has not completed." 1>&2)
		exit 1
	fi
done	
mkdir -p ${PROJECT}/${SAMPLE}
if [ ! -f ${WORK_PATH}/script_tar.done ]
then
	cmd="srun tar --exclude-vcs -cf ${WORK_PATH}/$(basename ${PBIN})_$(date +%F_%H-%M-%S_%Z).tar -C $(dirname ${PBIN}) $(basename ${PBIN})"
	echo $cmd
	eval $cmd || exit 1$?
	touch ${WORK_PATH}/script_tar.done
fi
if [ ! -f ${WORK_PATH}/move.done ]
then
	COUNT=0
	cmd="rsync -avP --exclude=*.done --exclude=slurm --exclude=jobReSubmit.sh ${WORK_PATH}/ ${PROJECT}/${SAMPLE}/"
	echo ${cmd}
	until [ $COUNT -gt 10 ] || eval ${cmd}
	do
		((COUNT++))
		sleep 20s
		(echo "--FAILURE--      Syncing files from ${WORKPATH} to ${PROJECT} failed. Retrying..." 1>&2)
	done
	if [ $COUNT -le 10 ]
	then
		touch ${WORK_PATH}/move.done
	else
		(echo "--FAILURE--      Unable to move files from ${WORK_PATH} to ${PROJECT}" 1>&2)
		exit 1
	fi
fi
