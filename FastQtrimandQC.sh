#!/bin/bash

DEFAULTTRIMPARAMETERS="ILLUMINACLIP:/resource/bundles/adapters/TruSeq3-PE-2.fa:2:30:10:1:true LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36" # eg ILLUMINACLIP:TruSeq3-PE-2.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36
if [ -z ${TRIMPARAMETERS} ]; then
	TRIMPARAMETERS=${DEFAULTTRIMPARAMETERS}
fi
export PBIN=$(dirname $0)
export SLSBIN=${PBIN}/slurmscripts
source ${PBIN}/HelperFunctions.sh

function usage () {
echo -e "\

\nThis script is designed to set up trimming jobs for fastq files, with FastQC run before and after.

usage: $0 options:

-h 	Print full help/usage information.

Required:

-s	Specify a sample name - ideally this should be in the form IndividualID_DNAID_LibID_RunID
	For a restart this needs to match exactly the previous sample name as it will be used to
	identify the working folder and the previous parameters entered.

-i	Input file. Two files are required so this should be specified twice. For a restart these
	filenames will be picked up from the previous parameterfile, so are not required, and any 
	input here will be ignored.
	
Optional:

-t	Trim parameters. 
	The default is set to: ${TRIMPARAMETERS}
	For a restart this value will be obtained from the previous parameter file, and any 
	input will be ignored.

-o 	If you wish to transfer the final output files to directory specify here.
	If it doesn't already exist it will be made. For a restart this value will be obtained
	from the previous parameter file, and any input here will be ignored.
	
"
}

while getopts "s:i:o:t:h" OPTION; do 
	case $OPTION in 
		s)
			SAMPLE="${OPTARG}"
			(printf "%-22s%s\n" "Sample ID" ${SAMPLE} 1>&2)
			export WORK_PATH=${SCRATCH}/${SAMPLE}
			if [ -f ${WORK_PATH}/parameters.sh ]; then
				source ${WORK_PATH}/parameters.sh
			fi
			;;
		i)
			if [ ! -f ${WORK_PATH}/parameters.sh ]; then
				if [ ! -e ${OPTARG} ]; then
					(echo "FAIL: Input file $OPTARG does not exist!" 1>&2)
					exit 1
				fi
				if [[ " ${FILELIST[@]} " =~ " ${OPTARG} " ]]
				then
					(echo "FAIL: Input file $OPTARG already added. Perhaps you want Read 2?" 1>&2)
					exit 1
				fi
				FILELIST=(${FILELIST[@]} ${OPTARG})
				(printf "%-22s%s\n" "Input file" $OPTARG 1>&2)
				if [[ ${#FILELIST[@]} -gt 2 ]]
				then
					(echo "FAIL: $OPTARG is the third input file specified. Only two are permitted!" 1>&2)
					exit 1
				fi
			fi
			;;
		o)
			PROJECT="${OPTARG}"
			(printf "%-22s%s\n" "Final output path" ${PROJECT} 1>&2)
			;;
		t)
			TRIMPARAMETERS="${OPTARG}"
			(printf "%-22s%s\n" "Trim parameters" ${TRIMPARAMETERS} 1>&2)
			;;
		h)
			usage
			exit 0
			;;
	esac
done
if [ -z ${SAMPLE} ]; then
	(echo "FAIL: No sample was specified!" 1>&2)
	exit 1
fi
mkdir -p ${WORK_PATH}
# need to complain and exit if no fastq files or output specified
if [ -z ${FILELIST[0]} ]; then
	echo "FAIL Read 1 not specified!"
	exit 1
fi
if [ -z ${FILELIST[1]} ]; then
	echo "FAIL Read 2 not specified!"
	exit 1
fi
# make the list of predicted trimmed files
TRIMFILELIST=(${WORK_PATH}/$(basename ${FILELIST[0]} .fastq.gz)_trimmed_paired.fastq.gz ${WORK_PATH}/$(basename ${FILELIST[0]} .fastq.gz)_trimmed_unpaired.fastq.gz ${WORK_PATH}/$(basename ${FILELIST[1]} .fastq.gz)_trimmed_paired.fastq.gz ${WORK_PATH}/$(basename ${FILELIST[1]} .fastq.gz)_trimmed_unpaired.fastq.gz)

# I am using a file to store these values rather than EXPORT because it allows a restart and ensures these values do not have to be re-entered - they should not change for a restart!
if [ ! -f ${WORK_PATH}/parameters.sh.done ]; then
	if [ -f ${WORK_PATH}/parameters.sh ]; then
		rm ${WORK_PATH}/parameters.sh
	fi
	echo -e "SAMPLE=\"${SAMPLE}\"" >> ${WORK_PATH}/parameters.sh
	echo -e "FILELIST=(${FILELIST[@]})" >> ${WORK_PATH}/parameters.sh
	echo -e "TRIMFILELIST=(${TRIMFILELIST[@]})" >> ${WORK_PATH}/parameters.sh
	echo -e "TRIMPARAMETERS=\"${TRIMPARAMETERS}\"" >> ${WORK_PATH}/parameters.sh
	echo -e "PROJECT=\"${PROJECT}\"" >> ${WORK_PATH}/parameters.sh
	touch ${WORK_PATH}/parameters.sh.done
fi

mkdir -p ${WORK_PATH}/slurm
# set up resubmission script 
echo $0 ${@} | tee ${WORK_PATH}/jobReSubmit.sh
chmod +x ${WORK_PATH}/jobReSubmit.sh
# before changing directory, get the current working directory so that we can come back to it for the final cleanup step
LAUNCHDIR=${PWD}
cd ${WORK_PATH}
#array job for fastq untrimmed (2 jobs on ${FILELIST[@]})
FastQCArray=""
for i in $(seq 1 ${#FILELIST[@]}); do
	FILE=${FILELIST[$(( ${i} - 1 ))]}
    if [ ! -e ${WORK_PATH}/FastQC/$(basename ${FILE} .fastq.gz).fastqc.done ]; then
         FastQCArray=$(appendList "$FastQCArray"  $i ",")
    fi
done
if [ "$FastQCArray" != "" ]; then
	fastqcjob=$(sbatch -J Fastqc_${SAMPLE}_untrimmed --array ${FastQCArray} ${SLSBIN}/FastQC.sl | awk '{print $4}')
	if [ $? -ne 0 ] || [ "$fastqcjob" == "" ]; then
		(printf "FAILED!\n" 1>&2)
		exit 1
	else
		echo "Fastqc_${SAMPLE} job is ${fastqcjob}"
		(printf "%sx%-4d [%s] Logs @ %s\n" "$fastqcjob" $(splitByChar "$FastQCArray" "," | wc -w) $(condenseList "$FastQCArray") "${WORK_PATH}/slurm/fastqc_${fastqcjob}_*.out" 1>&2)
	fi
fi 

#trim job - no dependencies
if [ ! -f "${WORK_PATH}/trim.done" ]; then
	trimjob=$(sbatch -J Trim_${SAMPLE} ${SLSBIN}/Trim.sl | awk '{print $4}')
	if [ $? -ne 0 ] || [ "$trimjob" == "" ]; then
		(printf "FAILED!\n" 1>&2)
		exit 1
	else
		echo "Trim_${SAMPLE} job is ${trimjob}"
		(printf "%s Log @ %s\n" "$trimjob" "${WORK_PATH}/slurm/trim_${trimjob}.out" 1>&2)
	fi
fi

# array job for fastq trimmed (on $TRIM{FILELIST[@]})
# dependent on trim job completions
FastQCArrayTrim=""
for i in $(seq 1 ${#TRIMFILELIST[@]}); do
	FILE=${TRIMFILELIST[$(( ${i} - 1 ))]}
    if [ ! -e ${WORK_PATH}/FastQC/$(basename ${FILE} .fastq.gz).fastqc.done ]; then
         FastQCArrayTrim=$(appendList "$FastQCArrayTrim"  $i ",")
    fi
done
if [ "$FastQCArrayTrim" != "" ]; then
	fastqctrimjob=$(sbatch -J Fastqc_${SAMPLE}_trimmed $(depCheck $trimjob) --array ${FastQCArrayTrim} ${SLSBIN}/FastQC.sl -t | awk '{print $4}')
	if [ $? -ne 0 ] || [ "$fastqctrimjob" == "" ]; then
		(printf "FAILED!\n" 1>&2)
		exit 1
	else
		echo "Fastqc_${SAMPLE}_trimmed job is ${fastqctrimjob}"
		(printf "%sx%-4d [%s] Logs @ %s\n" "$fastqctrimjob" $(splitByChar "$FastQCArrayTrim" "," | wc -w) $(condenseList "$FastQCArrayTrim") "${WORK_PATH}/slurm/fastqc_${fastqcjob}_*.out" 1>&2)
	fi
fi 
# rsync job transfer to final destination 
# dependent on trimmed fastqc job completion - should also be dependent of untrimmed fastqc job completion but isn't yet
if [ ! -f "${WORK_PATH}/move.done" ]; then
	transferjob=$(sbatch -J Transfer_${SAMPLE} $(depCheck $fastqctrimjob) ${SLSBIN}/Transfer.sl | awk '{print $4}')
	if [ $? -ne 0 ] || [ "$transferjob" == "" ]; then
		(printf "FAILED!\n" 1>&2)
		exit 1
	else
		echo "Transfer_${SAMPLE} job is ${transferjob}"
		(printf "%s Log @ %s\n" "$transferjob" "${WORK_PATH}/slurm/transfer_${transferjob}.out" 1>&2)
	fi
fi
cd ${LAUNCHDIR}
# clean 
# dependent on transfer job completion 
cleanjob=$(sbatch -J Clean_${SAMPLE} $(depCheck $transferjob) ${SLSBIN}/Cleanup.sl | awk '{print $4}')
if [ $? -ne 0 ] || [ "$cleanjob" == "" ]; then
	(printf "FAILED!\n" 1>&2)
	exit 1
else
	echo "Clean_${SAMPLE} job is ${cleanjob}"
	(printf "%s Log @ %s\n" "$cleanjob" "${LAUNCHDIR}/cleanuptrim_${cleanjob}.out" 1>&2)
fi
