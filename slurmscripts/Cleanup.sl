#!/bin/bash
#SBATCH --job-name Cleanup
#SBATCH --time	1:00:00
#SBATCH --mem	1G
#SBATCH --error cleanuptrim_%j.out
#SBATCH --output cleanuptrim_%j.out

source ${WORK_PATH}/parameters.sh
if [ -f ${WORK_PATH}/move.done ]
then
	if [ ! -f ${WORK_PATH}/slurm_tar.done ]
	then
		cmd="srun tar --exclude-vcs -cf ${PROJECT}/${SAMPLE}/slurm.tar ${WORK_PATH}/slurm"
		echo $cmd
		eval $cmd || exit 1$?
		touch ${WORK_PATH}/slurm_tar.done
	fi
	rm -r ${WORK_PATH}
	(echo "The trim and fastqc processing for ${SAMPLE} is complete and this file can be deleted." 1>&2)
else
	(echo "Cannot delete ${WORK_PATH} as transfer to final destination is not complete." 1>&2)
	exit 1
fi

